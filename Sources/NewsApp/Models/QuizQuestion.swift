import Foundation

enum QuizQuestionType: String, Codable {
	case trueOrFalse = "truefalse"
	case multipleChoice = "multiplechoice"
}

struct QuizQuestion: Codable, Identifiable {
	var id: UUID = UUID()
	let type: QuizQuestionType
	let question: String
	let options: [String]
	let correctIndex: Int
	let explanation: String

	enum CodingKeys: String, CodingKey {
		case type, question, options, correctIndex, explanation
	}
}

struct QuizResult: Identifiable {
	var id: Int64?
	var articleId: String
	var articleTitle: String
	var score: Int
	var totalQuestions: Int
	var completedAt: Date

	var percentage: Int {
		totalQuestions > 0 ? Int(Double(score) / Double(totalQuestions) * 100) : 0
	}
}

struct QuizPeriodStats {
	let correct: Int
	let total: Int
	let quizCount: Int

	var percentage: Int {
		total > 0 ? Int(Double(correct) / Double(total) * 100) : 0
	}
}
