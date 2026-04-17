import Foundation

enum QuizQuestionType: String, Codable {
	case trueOrFalse = "truefalse"
	case multipleChoice = "multiplechoice"

	// Accept whatever variation the model returns (true_false, multiple-choice, tf, mc, etc.)
	init(from decoder: Decoder) throws {
		let raw = try decoder.singleValueContainer().decode(String.self)
			.lowercased()
			.replacingOccurrences(of: "_", with: "")
			.replacingOccurrences(of: "-", with: "")
			.replacingOccurrences(of: " ", with: "")
		switch raw {
		case "truefalse", "tf", "trueorfalse", "boolean", "trueorfalseq":
			self = .trueOrFalse
		default:
			self = .multipleChoice
		}
	}
}

struct QuizQuestion: Identifiable {
	var id: UUID = UUID()
	let type: QuizQuestionType
	let question: String
	let options: [String]
	let correctIndex: Int
	let explanation: String
	/// Verbatim excerpt from the source paragraph used to generate this question.
	/// Used to scroll the article to the relevant section when the explanation is revealed.
	var paragraphHint: String?
}

extension QuizQuestion: Codable {
	enum CodingKeys: String, CodingKey {
		case type, question, options, correctIndex, explanation
		case paragraphHint = "sourceExcerpt"
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id            = UUID()
		type          = try c.decode(QuizQuestionType.self, forKey: .type)
		question      = try c.decode(String.self, forKey: .question)
		options       = try c.decode([String].self, forKey: .options)
		explanation   = (try? c.decode(String.self, forKey: .explanation)) ?? ""
		paragraphHint = try? c.decode(String.self, forKey: .paragraphHint)
		// Some models return correctIndex as a string (e.g. "2") — handle both
		if let intVal = try? c.decode(Int.self, forKey: .correctIndex) {
			correctIndex = intVal
		} else if let strVal = try? c.decode(String.self, forKey: .correctIndex),
				  let intVal = Int(strVal) {
			correctIndex = intVal
		} else {
			correctIndex = 0
		}
	}
}

struct QuizDisputeResult: Equatable {
	let userIsCorrect: Bool
	let isQuestionInvalid: Bool
	let correctedAnswerIndex: Int
	let explanation: String
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
