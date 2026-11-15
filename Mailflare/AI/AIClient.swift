import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AIToolCall {
	var id: String
	var name: String
	var arguments: String
}

enum AIStreamEvent {
	case text(String)
	case toolCalls([AIToolCall])
}

struct AIError: LocalizedError {
	let message: String
	var errorDescription: String? { message }
}

/// All AI requests run through Apple's on-device Foundation Model. This client has no network path.
struct AIClient {
	static var isAvailable: Bool {
		#if canImport(FoundationModels)
		if #available(macOS 26.0, *) {
			if case .available = SystemLanguageModel.default.availability { return true }
		}
		#endif
		return false
	}

	static var availabilityDescription: String {
		#if canImport(FoundationModels)
		if #available(macOS 26.0, *) {
			switch SystemLanguageModel.default.availability {
			case .available:
				return "Apple Intelligence is available. AI requests run on this Mac."
			case .unavailable(let reason):
				switch reason {
				case .deviceNotEligible:
					return "This Mac does not support Apple Intelligence."
				case .appleIntelligenceNotEnabled:
					return "Turn on Apple Intelligence in System Settings to use on-device AI."
				case .modelNotReady:
					return "Apple Intelligence is preparing its on-device model. Try again when it finishes downloading."
				@unknown default:
					return "On-device AI is currently unavailable on this Mac."
				}
			@unknown default:
				return "On-device AI is currently unavailable on this Mac."
			}
		}
		return "On-device AI requires macOS 26 or later."
		#else
		return "This build needs an SDK with Apple's Foundation Models framework."
		#endif
	}

	/// Kept as an async stream for the chat UI. Foundation Models currently returns a complete turn;
	/// tool calls use a small JSON envelope so the existing local mail actions can remain approval-gated.
	func stream(messages: [[String: Any]], tools: [[String: Any]]) -> AsyncThrowingStream<AIStreamEvent, Error> {
		AsyncThrowingStream { continuation in
			let task = Task {
				do {
					let answer = try await Self.respond(messages: messages, tools: tools)
					if tools.isEmpty {
						continuation.yield(.text(answer))
					} else if let envelope = Self.toolEnvelope(answer), !envelope.calls.isEmpty {
						if !envelope.content.isEmpty { continuation.yield(.text(envelope.content)) }
						continuation.yield(.toolCalls(envelope.calls))
					} else if let envelope = Self.toolEnvelope(answer) {
						continuation.yield(.text(envelope.content))
					} else {
						continuation.yield(.text(answer))
					}
					continuation.finish()
				} catch {
					continuation.finish(throwing: error)
				}
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	private static func respond(messages: [[String: Any]], tools: [[String: Any]]) async throws -> String {
		guard isAvailable else { throw AIError(message: availabilityDescription) }
		#if canImport(FoundationModels)
		if #available(macOS 26.0, *) {
			let system = messages.first(where: { $0["role"] as? String == "system" })?["content"] as? String ?? "You are a helpful assistant."
			let historyLimit = tools.isEmpty ? 3 : 12
			let characterBudget = tools.isEmpty ? 10_000 : 7_000
			let rendered = messages.filter { $0["role"] as? String != "system" }.suffix(historyLimit).map(Self.render).joined(separator: "\n\n")
			let turns = String(rendered.suffix(characterBudget))
			let prompt: String
			if tools.isEmpty {
				prompt = turns
			} else {
				let schema = (try? JSONSerialization.data(withJSONObject: tools, options: [.sortedKeys]))
					.map { String(decoding: $0, as: UTF8.self) } ?? "[]"
				prompt = """
				\(turns)

				Available local tools (JSON schemas):
				\(schema)

				Return exactly one JSON object and no Markdown. Use this shape:
				{"content":"brief user-facing text, or empty when using a tool","tool_calls":[{"name":"tool name","arguments":{}}]}
				If no tool is needed, set tool_calls to []. Only call tools from the list. Arguments must match their schema. Never claim an action succeeded before seeing its result.
				"""
			}
			let session = LanguageModelSession(instructions: system)
			let response = try await session.respond(to: prompt)
			let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !text.isEmpty else { throw AIError(message: "The on-device model returned no text. Try a shorter request.") }
			return text
		}
		#endif
		throw AIError(message: availabilityDescription)
	}

	private static func render(_ message: [String: Any]) -> String {
		let role = message["role"] as? String ?? "user"
		let content = message["content"] as? String ?? ""
		if role == "assistant", let calls = message["tool_calls"] as? [[String: Any]], !calls.isEmpty {
			let description = calls.compactMap { call -> String? in
				guard let function = call["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
				return "\(name)(\(function["arguments"] as? String ?? "{}"))"
			}.joined(separator: ", ")
			return "ASSISTANT TOOL REQUEST: \(description)\nASSISTANT: \(content)"
		}
		if role == "tool" { return "UNTRUSTED TOOL RESULT: \(content)" }
		return "\(role.uppercased()): \(content)"
	}

	private static func toolEnvelope(_ response: String) -> (content: String, calls: [AIToolCall])? {
		var json = response.trimmingCharacters(in: .whitespacesAndNewlines)
		if json.hasPrefix("```") {
			json = json.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
			if let end = json.range(of: "```", options: .backwards) { json = String(json[..<end.lowerBound]) }
		}
		guard let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
		let rawCalls = (object["tool_calls"] as? [[String: Any]]) ?? (object["toolCalls"] as? [[String: Any]]) ?? []
		let calls = rawCalls.compactMap { item -> AIToolCall? in
			let function = item["function"] as? [String: Any] ?? item
			guard let name = function["name"] as? String, !name.isEmpty else { return nil }
			let arguments = function["arguments"]
			let argumentData: Data
			if let text = arguments as? String { argumentData = text.data(using: .utf8) ?? Data("{}".utf8) }
			else if let arguments, JSONSerialization.isValidJSONObject(arguments), let data = try? JSONSerialization.data(withJSONObject: arguments) { argumentData = data }
			else { argumentData = Data("{}".utf8) }
			return AIToolCall(id: UUID().uuidString, name: name, arguments: String(decoding: argumentData, as: UTF8.self))
		}
		return (object["content"] as? String ?? "", calls)
	}
}
