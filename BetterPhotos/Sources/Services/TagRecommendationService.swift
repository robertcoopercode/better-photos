import Foundation
import NaturalLanguage

/// Service that recommends existing tags from the user's library based on Vision analysis results.
/// Uses Apple's NaturalLanguage framework for semantic similarity matching.
class TagRecommendationService {
    private let embedding: NLEmbedding?

    init() {
        self.embedding = NLEmbedding.wordEmbedding(for: .english)
    }

    /// Recommends existing tags that are semantically similar to Vision analysis results
    /// - Parameters:
    ///   - visionSuggestions: Tags suggested by Vision (what's in the image)
    ///   - existingTags: All known tags from the user's library
    ///   - currentTags: Tags already applied to the photo (to filter out)
    ///   - limit: Maximum number of recommendations to return
    /// - Returns: Array of TagSuggestion with similarity scores
    func recommendTags(
        fromVisionSuggestions visionSuggestions: [TagSuggestion],
        existingTags: [String],
        currentTags: [String],
        limit: Int = 10
    ) -> [TagSuggestion] {
        guard !visionSuggestions.isEmpty, !existingTags.isEmpty else {
            return []
        }

        // Filter out tags already applied to the photo
        let currentTagsLower = Set(currentTags.map { $0.lowercased() })
        let availableTags = existingTags.filter { !currentTagsLower.contains($0.lowercased()) }

        guard !availableTags.isEmpty else {
            return []
        }

        // Get all Vision terms (split multi-word suggestions into individual words)
        let visionTerms = extractTerms(from: visionSuggestions)

        // Score each existing tag by its similarity to Vision terms
        var tagScores: [(tag: String, score: Double)] = []

        for tag in availableTags {
            let score = calculateSimilarity(tag: tag, visionTerms: visionTerms, visionSuggestions: visionSuggestions)
            if score > 0.05 { // Minimum threshold to filter noise
                tagScores.append((tag, score))
            }
        }

        // Sort by score descending and take top N
        tagScores.sort { $0.score > $1.score }

        return tagScores.prefix(limit).map { item in
            TagSuggestion(
                tag: item.tag,
                confidence: min(item.score, 1.0), // Cap at 1.0
                source: .recommended
            )
        }
    }

    /// Extracts individual terms from Vision suggestions for matching
    private func extractTerms(from suggestions: [TagSuggestion]) -> [(term: String, weight: Double)] {
        var terms: [(String, Double)] = []

        for suggestion in suggestions {
            // Split by spaces and common separators
            let words = suggestion.tag
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count > 2 } // Skip very short words

            for word in words {
                // Weight by the original confidence
                terms.append((word, suggestion.confidence))
            }

            // Also add the full tag as a term for exact/close matching
            let fullTag = suggestion.tag.lowercased()
            if !fullTag.isEmpty {
                terms.append((fullTag, suggestion.confidence * 1.5)) // Boost full tag matches
            }
        }

        return terms
    }

    /// Calculates similarity score between an existing tag and Vision terms
    private func calculateSimilarity(
        tag: String,
        visionTerms: [(term: String, weight: Double)],
        visionSuggestions: [TagSuggestion]
    ) -> Double {
        let tagLower = tag.lowercased()

        // Check for exact match with any Vision suggestion (highest priority)
        for suggestion in visionSuggestions {
            if tagLower == suggestion.tag.lowercased() {
                return 1.0 * suggestion.confidence + 0.5
            }
        }

        // Check for substring matches (tag contains or is contained by Vision term)
        var substringBonus: Double = 0
        for (term, weight) in visionTerms {
            if tagLower.contains(term) || term.contains(tagLower) {
                substringBonus = max(substringBonus, weight * 0.8)
            }
        }

        // Calculate embedding-based similarity
        var embeddingScore: Double = 0
        if let embedding = embedding {
            embeddingScore = calculateEmbeddingSimilarity(tag: tagLower, visionTerms: visionTerms, embedding: embedding)
        }

        // Combine scores with weights
        return max(substringBonus, embeddingScore)
    }

    /// Calculates semantic similarity using word embeddings
    private func calculateEmbeddingSimilarity(
        tag: String,
        visionTerms: [(term: String, weight: Double)],
        embedding: NLEmbedding
    ) -> Double {
        // Get embedding for the tag (handle multi-word tags)
        let tagWords = tag.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard !tagWords.isEmpty else { return 0 }

        // Calculate weighted average similarity to all Vision terms
        var totalScore: Double = 0
        var totalWeight: Double = 0

        for (term, weight) in visionTerms {
            // Get best similarity between any tag word and the vision term
            var bestSimilarity: Double = 0

            for tagWord in tagWords {
                // Check if both words have embeddings before computing distance
                guard embedding.contains(tagWord), embedding.contains(term) else {
                    continue
                }

                let distance = embedding.distance(between: tagWord, and: term)
                // Convert distance to similarity (distance is 0-2, we want 0-1 similarity)
                let similarity = max(0, 1.0 - distance / 2.0)
                bestSimilarity = max(bestSimilarity, similarity)
            }

            totalScore += bestSimilarity * weight
            totalWeight += weight
        }

        return totalWeight > 0 ? totalScore / totalWeight : 0
    }
}
