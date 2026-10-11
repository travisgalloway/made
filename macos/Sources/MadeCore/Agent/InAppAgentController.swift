import Foundation
import Observation

public struct AgentChatMessage: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let sender: String // "user" or "assistant"
    public let text: String
    public let timestamp: Date
    public let toolExecuted: String?
    
    public init(sender: String, text: String, toolExecuted: String? = nil) {
        self.id = UUID()
        self.sender = sender
        self.text = text
        self.timestamp = Date()
        self.toolExecuted = toolExecuted
    }
}

@Observable
public final class InAppAgentController: @unchecked Sendable {
    public private(set) var messages: [AgentChatMessage] = []
    public private(set) var isProcessing: Bool = false
    public let toolRegistry: CADToolRegistry
    
    public init(toolRegistry: CADToolRegistry) {
        self.toolRegistry = toolRegistry
        
        // Welcome message
        messages.append(AgentChatMessage(
            sender: "assistant",
            text: "Hello! I am your CAD Copilot. You can tell me to modify dimensions, create new solids, measure parts, or ask questions about the scene."
        ))
    }
    
    public func sendPrompt(_ userPrompt: String) async {
        let trimmed = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        await MainActor.run {
            messages.append(AgentChatMessage(sender: "user", text: trimmed))
            isProcessing = true
        }
        
        let response = await interpretAndExecute(trimmed)
        
        await MainActor.run {
            messages.append(response)
            isProcessing = false
        }
    }
    
    private func interpretAndExecute(_ prompt: String) async -> AgentChatMessage {
        let lower = prompt.lowercased()
        
        // 1. Measure commands
        if lower.contains("measure") || lower.contains("volume") || lower.contains("dimensions of") {
            let targetId = lower.contains("cylinder") ? "cylinder-1" : "box-1"
            let result = await toolRegistry.callTool(name: "cad_measure", arguments: ["id": .string(targetId)])
            let text = result.content.first?.text ?? "Measurement completed."
            return AgentChatMessage(sender: "assistant", text: "Measurement for \(targetId):\n\(text)", toolExecuted: "cad_measure")
        }
        
        // 2. Boolean CSG operations (Euclid engine)
        if lower.contains("subtract") || lower.contains("cut") || lower.contains("drill") {
            let result = await toolRegistry.callTool(name: "cad_boolean_operation", arguments: [
                "solidA": .string("box-1"),
                "solidB": .string("cylinder-1"),
                "operation": .string("subtract")
            ])
            let text = result.content.first?.text ?? "Subtracted cylinder from box."
            return AgentChatMessage(sender: "assistant", text: text, toolExecuted: "cad_boolean_operation")
        }
        
        if lower.contains("union") || lower.contains("combine") || lower.contains("fuse") {
            let result = await toolRegistry.callTool(name: "cad_boolean_operation", arguments: [
                "solidA": .string("box-1"),
                "solidB": .string("cylinder-1"),
                "operation": .string("union")
            ])
            let text = result.content.first?.text ?? "Combined box and cylinder."
            return AgentChatMessage(sender: "assistant", text: text, toolExecuted: "cad_boolean_operation")
        }
        
        // 2. Add solid commands
        if lower.contains("add box") || lower.contains("create box") || lower.contains("new box") {
            var width: Double = 40
            var depth: Double = 30
            var height: Double = 20
            
            // Extract numbers if present
            let numbers = extractNumbers(from: prompt)
            if numbers.count >= 3 {
                width = numbers[0]
                depth = numbers[1]
                height = numbers[2]
            }
            
            let args: [String: AnyCodableValue] = [
                "type": .string("box"),
                "width": .double(width),
                "depth": .double(depth),
                "height": .double(height),
                "posX": .double(Double.random(in: -30...30)),
                "posY": .double(Double.random(in: -30...30))
            ]
            let result = await toolRegistry.callTool(name: "cad_add_solid", arguments: args)
            let text = result.content.first?.text ?? "Added box."
            return AgentChatMessage(sender: "assistant", text: text, toolExecuted: "cad_add_solid")
        }
        
        if lower.contains("add cylinder") || lower.contains("create cylinder") {
            var radius: Double = 15
            var height: Double = 40
            let numbers = extractNumbers(from: prompt)
            if numbers.count >= 2 {
                radius = numbers[0]
                height = numbers[1]
            }
            
            let args: [String: AnyCodableValue] = [
                "type": .string("cylinder"),
                "radius": .double(radius),
                "height": .double(height),
                "posX": .double(Double.random(in: -30...30)),
                "posY": .double(Double.random(in: -30...30))
            ]
            let result = await toolRegistry.callTool(name: "cad_add_solid", arguments: args)
            let text = result.content.first?.text ?? "Added cylinder."
            return AgentChatMessage(sender: "assistant", text: text, toolExecuted: "cad_add_solid")
        }
        
        // 3. Modify parameter commands
        if lower.contains("width") || lower.contains("wide") {
            let targetId = lower.contains("cylinder") ? "cylinder-1" : "box-1"
            let num = extractNumbers(from: prompt).first ?? 50.0
            let result = await toolRegistry.callTool(name: "cad_set_param", arguments: [
                "id": .string(targetId),
                "param": .string("width"),
                "value": .double(num)
            ])
            return AgentChatMessage(sender: "assistant", text: result.content.first?.text ?? "Updated width.", toolExecuted: "cad_set_param")
        }
        
        if lower.contains("depth") {
            let targetId = lower.contains("cylinder") ? "cylinder-1" : "box-1"
            let num = extractNumbers(from: prompt).first ?? 40.0
            let result = await toolRegistry.callTool(name: "cad_set_param", arguments: [
                "id": .string(targetId),
                "param": .string("depth"),
                "value": .double(num)
            ])
            return AgentChatMessage(sender: "assistant", text: result.content.first?.text ?? "Updated depth.", toolExecuted: "cad_set_param")
        }
        
        if lower.contains("height") || lower.contains("tall") {
            let targetId = lower.contains("cylinder") ? "cylinder-1" : "box-1"
            let num = extractNumbers(from: prompt).first ?? 60.0
            let result = await toolRegistry.callTool(name: "cad_set_param", arguments: [
                "id": .string(targetId),
                "param": .string("height"),
                "value": .double(num)
            ])
            return AgentChatMessage(sender: "assistant", text: result.content.first?.text ?? "Updated height.", toolExecuted: "cad_set_param")
        }
        
        if lower.contains("radius") {
            let num = extractNumbers(from: prompt).first ?? 20.0
            let result = await toolRegistry.callTool(name: "cad_set_param", arguments: [
                "id": .string("cylinder-1"),
                "param": .string("radius"),
                "value": .double(num)
            ])
            return AgentChatMessage(sender: "assistant", text: result.content.first?.text ?? "Updated radius.", toolExecuted: "cad_set_param")
        }
        
        // 4. Query scene
        if lower.contains("scene") || lower.contains("list") || lower.contains("show") || lower.contains("what") {
            let result = await toolRegistry.callTool(name: "cad_get_scene", arguments: [:])
            return AgentChatMessage(sender: "assistant", text: "Current Scene Objects:\n\(result.content.first?.text ?? "[]")", toolExecuted: "cad_get_scene")
        }
        
        return AgentChatMessage(
            sender: "assistant",
            text: "I understand CAD intents like:\n• 'Set box width to 60 mm'\n• 'Set cylinder height to 80 mm'\n• 'Add box 50 30 20'\n• 'Add cylinder with radius 20 height 50'\n• 'Measure box-1'\n• 'Show scene'"
        )
    }
    
    private func extractNumbers(from text: String) -> [Double] {
        let pattern = #"[-+]?[0-9]*\.?[0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return Double(text[range])
        }
    }
}
