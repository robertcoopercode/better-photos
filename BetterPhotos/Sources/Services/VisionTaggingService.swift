import Vision
import AppKit

class VisionTaggingService {
    private var resultsCache: [String: [TagSuggestion]] = [:]

    func analyzeTags(for image: CGImage, cacheKey: String? = nil) async throws -> [TagSuggestion] {
        // Check cache
        if let key = cacheKey, let cached = resultsCache[key] {
            return cached
        }

        let suggestions = try await performAnalysis(image: image)

        // Cache results
        if let key = cacheKey {
            resultsCache[key] = suggestions
        }

        return suggestions
    }

    private func performAnalysis(image: CGImage) async throws -> [TagSuggestion] {
        try await withCheckedThrowingContinuation { continuation in
            let classificationRequest = VNClassifyImageRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let suggestions = results
                    .filter { $0.confidence > 0.3 }  // 30% confidence threshold
                    .prefix(15)  // Top 15 results
                    .map { observation in
                        TagSuggestion(
                            tag: self.formatTag(observation.identifier),
                            confidence: Double(observation.confidence),
                            source: .appleVision
                        )
                    }

                continuation.resume(returning: Array(suggestions))
            }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([classificationRequest])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func formatTag(_ identifier: String) -> String {
        // Vision returns identifiers like "outdoor_mountain" or "food_pizza"
        // Convert to human-readable format
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: ", ")
            .first ?? identifier
    }

    func clearCache() {
        resultsCache.removeAll()
    }

    func clearCache(for key: String) {
        resultsCache.removeValue(forKey: key)
    }
}
