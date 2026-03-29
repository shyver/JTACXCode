import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

class JTACLLMParser: ObservableObject, @unchecked Sendable {
    @Published var isParsing = false
    @Published var downloadProgress: Double = 0.0
    @Published var isDownloading = false
    
    private var modelContext: ModelContext?
    
    let modelID = "mlx-community/Llama-3.2-1B-Instruct-4bit"

    init() {
        // Pre-warm / pre-load the model in the background if desired
        Task {
            await ensureModelLoaded()
        }
    }
    
    private func ensureModelLoaded() async -> Bool {
        if modelContext != nil { return true }
        
        Task { @MainActor in
            self.isDownloading = true
        }
        
        do {
            let context = try await MLXLMCommon.loadModel(id: modelID) { progress in
                Task { @MainActor in
                    self.downloadProgress = progress.fractionCompleted
                }
            }
            
            self.modelContext = context
            
            Task { @MainActor in
                self.isDownloading = false
            }
            return true
            
        } catch {
            print("[JTACLLMParser] Failed to load model: \(error)")
            Task { @MainActor in
                self.isDownloading = false
            }
            return false
        }
    }
    
    func parse(transcript: String, completion: @escaping @Sendable (JTACReport) -> Void) {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(JTACReport())
            return
        }
        
        Task {
            let loaded = await ensureModelLoaded()
            guard loaded, let context = modelContext else {
                Task { @MainActor in completion(JTACReport()) }
                return
            }
            
            Task { @MainActor in self.isParsing = true }
            
            let systemInstruction = """
            You are an expert military communications data extractor.
            Given the following radio transcript, extract the details into a strict JSON format. 
            Do NOT include any extra conversational text outside the JSON.
            If a field is not present in the transcript, output null for that field.

            Use this exact JSON schema:
            {
              "cas": {
                "callsign": "string", "mission": "string", "aircraftType": "string",
                "posAndAlt": "string", "ordnance": "string", "playtime": "string",
                "capes": "string", "laserCode": "string", "vdlCode": "string",
                "abortCode": "string", "type": "string", "control": "string"
              },
              "situationUpdate": {
                "threats": "string", "targets": "string", "friendlies": "string",
                "arty": "string", "clearance": "string", "ordnance": "string", "remarks": "string"
              },
              "gamePlan": {
                "typeOfControl": "string", "methodOfAttack": "string", "gcIntent": "string",
                "cde": "string", "ordnance": "string", "desiredEffect": "string"
              },
              "safetyOfFlight": {
                 "threats": "string", "friendlyAssets": "string", "terrainsObstacles": "string",
                 "emergencyConsiderations": "string", "ePoint": "string"
              },
              "nineLine": {
                "ip": "string", "heading": "string", "distance": "string", "targetElevation": "string",
                "targetDescription": "string", "targetMark": "string", "friendlies": "string",
                "egress": "string", "remarksLine": "string"
              }
            }
            """
            
            let prompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(systemInstruction)<|eot_id|><|start_header_id|>user<|end_header_id|>\n\nTranscript:\n\(transcript)\n\nExtract the JSON data now:<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
            
            do {
                let userInput = UserInput(prompt: prompt)
                let lmInput = try await context.processor.prepare(input: userInput)
                
                var generatedText = ""
                let parameters = GenerateParameters(temperature: 0.1, topP: 0.9)
                
                let stream = try MLXLMCommon.generate(
                    input: lmInput,
                    parameters: parameters,
                    context: context
                )
                
                var tokenCount = 0
                for try await generation in stream {
                    if let chunk = generation.chunk {
                        generatedText += chunk
                        tokenCount += 1
                        if tokenCount >= 1024 { break }
                    }
                }
                
                print("[JTACLLMParser] LLM Raw Output:\n\(generatedText)")
                
                // Parse JSON
                if let report = self.extractJTACReport(from: generatedText) {
                    Task { @MainActor in
                        self.isParsing = false
                        completion(report)
                    }
                } else {
                    print("[JTACLLMParser] Failed to decode JSON from generation.")
                    Task { @MainActor in
                        self.isParsing = false
                        completion(JTACReport())
                    }
                }
            } catch {
                print("[JTACLLMParser] Execution error: \(error)")
                Task { @MainActor in
                    self.isParsing = false
                    completion(JTACReport())
                }
            }
        }
    }
    
    private func extractJTACReport(from text: String) -> JTACReport? {
        guard let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}") else {
            return nil
        }
        
        let jsonStr = String(text[first...last])
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        
        do {
            return try JSONDecoder().decode(JTACReport.self, from: data)
        } catch {
            print("[JTACLLMParser] JSON Decode Error: \(error)\nAttempting to recover...")
            // We can return a partial / empty one if we want, but returning nil handles it natively.
            return nil
        }
    }
}
