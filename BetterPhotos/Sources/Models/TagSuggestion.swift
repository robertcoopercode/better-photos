import Foundation

struct TagSuggestion: Identifiable, Equatable {
    let id: UUID
    let tag: String
    let confidence: Double
    let source: TagSource

    init(tag: String, confidence: Double, source: TagSource = .appleVision) {
        self.id = UUID()
        self.tag = tag
        self.confidence = confidence
        self.source = source
    }

    enum TagSource: String, Codable {
        case appleVision
        case userHistory
        case manual
        case recommended  // Existing tags recommended based on Vision analysis
    }

    var confidencePercentage: Int {
        Int(confidence * 100)
    }
}
