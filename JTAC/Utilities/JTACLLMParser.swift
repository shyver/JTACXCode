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
            If a field is not present in the transcript, output "" (an empty string) for that field, do NOT output null.
            
            IMPORTANT: For fields mapping to specific military terms (e.g. ordnances, threats, friendlies, target types, egress directions), you MUST match them to the reference vocabulary provided below. Speech-to-text is flawed, so interpret phonetic mistakes and map them to the closest term from the reference vocabulary. For example, "tattoo control" is "type 2 control", "bump on target" is "bomb on target", "market to" is "mk 82", etc.
            Coordinates, headings, distances, elevations, and times are not restricted to this list.
            
            Reference Vocabulary:
            - Threats: No threat except small arms and possible manpads, M163 Vulcan, M167 VADS, M6 Linebacker, Avenger, Chaparral, NASAMS, MIM-23 HAWK, MIM-104 PATRIOT, THAAD, ZSU-23-4 Shilka, ZSU-57-2, Pantsir-S1, Tor-M1, 2K12 Kub, Buk-M1, S-200, S-300, S-400
            - Friendly Assets: F-5E/F, Falcon, Zoomer, Diver, Shooter, L59 Albatros, T6-Texan, Lynx, ASAD, UH-60 Blackhawk, OH-58 Kiowa, Viper, AB-205, Tiger, C-130J/H, Hercule, Tanit, L410, Manar, AS-350 Ecureuil, Fahd, Gazzelle, Anka, eagle, C-208, Scout, Skybird
            - Terrain/Obstacles: mountain, hills, sudden terrain rise, open desert, river, lake, bird hazards, limited emergency landing zone, obstacle avoidance, high-rise buildings, power lines, transmission tower, Radio TV antenna
            - Targets: Vehicle, Tank, MBT, APC, IFC, Armored Vehicle, truck, Technical, Convoy, Column, Personnel, Infantry, Dismounted, squad, platoon, troops, fighters, insurgents, structures, buildings, compound, house, bunker, trench, position, fortification, warehouse, AAA, SAM, MANPAD, Heavy machinegun, machinegun, mortar, artillery, rocket launcher
            - Target States: moving, stationary, dug-in, fortified, exposed, concealed, dispersed, concentrated, high value, priority, command post
            - Ordnance: rockets, gun, missiles, air to ground missiles, mk 82, mk 83, mk 84, gbu 10, gbu 12, gbu 16, hydra 70, APKWS, AGM-114 Hellfire, AGM-65 Maverick, AGM-88 HARM, GBU 31, GBU 38, GBU 32
            - Game Plan Control Type: 1, 2, 3
            - Method of Attack: Bomb on target (BOT), Bomb on coordinate (BOC)
            - Commander Intent: Support, Protect, Enable, Deny, Destroy, Disrupt, Secure, neutralize, suppress, engage, cover, defend, delay, observe
            - Desired Effect: Destroy, Neutralize, Suppress, Disable, Disrupt
            - Target Mark: Smoke, IR pointer, laser, beacon, strobe, panel, flare, Talk on
            - Directions/Egress: north, south, east, west, north east, south east, south west, north west, as pilot discretion, as required, as needed
            - ACAs status: active, established, in effect, cold, hot

            Use this exact JSON schema. NEVER output the `cas` property. If information is not mentioned, use `""`:
            {
              "situationUpdate": {
                "threats": "", "targets": "", "friendlies": "",
                "arty": "", "clearance": "", "ordnance": "", "remarks": ""
              },
              "gamePlan": {
                "typeOfControl": "", "methodOfAttack": "", "gcIntent": "",
                "cde": "", "ordnance": "", "desiredEffect": ""
              },
              "safetyOfFlight": {
                 "threats": "", "friendlyAssets": "", "terrainsObstacles": "",
                 "emergencyConsiderations": "", "ePoint": ""
              },
              "nineLine": {
                "ip": "", "heading": "", "distance": "", "targetElevation": "",
                "targetDescription": "", "targetMark": "", "friendlies": "",
                "egress": "", "remarksLine": ""
              },
              "remarks": {
                "laserTgtLine": "", "ptl": "", "gunTgtLine": "", "maxOrd": "", "text": ""
              },
              "restrictions": {
                "dangerClose": "", "fah": "", "acas": "", "totTtt": "", "latAlt": "", "postLaunchAbort": "", "text": ""
              },
              "bda": {
                "status": "", "size": "", "activity": "", "location": "", "time": "", "remarks": "", "text": ""
              }
            }
            """
            
            let prompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(systemInstruction)<|eot_id|><|start_header_id|>user<|end_header_id|>\n\nTranscript:\n\(transcript)\n\nExtract the JSON data now:<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
            
            do {
                let userInput = UserInput(prompt: prompt)
                
                print("[JTACLLMParser] -------------- SENDING REQUEST TO LLM --------------")
                print("[JTACLLMParser] Preparing input for MLX processor...")
                
                let lmInput = try await context.processor.prepare(input: userInput)
                
                print("[JTACLLMParser] Input prepared. Beginning stream generation...")
                
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
                
                print("[JTACLLMParser] -------------- LLM RESPONDED --------------")
                print("[JTACLLMParser] LLM Raw Output:\n\(generatedText)")
                print("[JTACLLMParser] ---------------------------------------------")
                
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
