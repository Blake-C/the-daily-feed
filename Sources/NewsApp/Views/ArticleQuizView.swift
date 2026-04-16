import SwiftUI

struct ArticleQuizView: View {
	let questions: [QuizQuestion]
	let isLoading: Bool
	let onClose: () -> Void
	let onScoreSaved: (Int, Int) -> Void

	@State private var selectedAnswers: [Int: Int] = [:]
	@State private var scoreSaved = false

	private var answeredCount: Int { selectedAnswers.count }
	private var isComplete: Bool { answeredCount == questions.count && !questions.isEmpty }
	private var correctCount: Int {
		selectedAnswers.reduce(0) { sum, pair in
			let (index, chosen) = pair
			return sum + (questions[index].correctIndex == chosen ? 1 : 0)
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			// Panel header
			HStack {
				Label("Test Your Knowledge", systemImage: "brain.head.profile")
					.font(.system(size: 13, weight: .semibold))
				Spacer()
				Button(action: onClose) {
					Image(systemName: "xmark.circle.fill")
						.font(.system(size: 15))
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 10)

			Divider()

			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					if isLoading {
						HStack(spacing: 10) {
							ProgressView().scaleEffect(0.8)
							Text("Generating questions…")
								.font(.system(size: 13))
								.foregroundStyle(.secondary)
						}
						.frame(maxWidth: .infinity, alignment: .center)
						.padding(.top, 40)
					} else if questions.isEmpty {
						Text("No questions available.")
							.font(.system(size: 13))
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity, alignment: .center)
							.padding(.top, 40)
					} else {
						aiDisclaimerBanner

						ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
							QuizQuestionCard(
								index: index,
								question: question,
								selectedAnswer: selectedAnswers[index],
								onSelect: { chosen in
									guard selectedAnswers[index] == nil else { return }
									selectedAnswers[index] = chosen
									checkAndSave()
								}
							)
						}

						if isComplete {
							scoreCard
						}
					}
				}
				.padding(14)
			}
		}
		.background(Color(NSColor.windowBackgroundColor))
	}

	// MARK: - Subviews

	private var aiDisclaimerBanner: some View {
		HStack(alignment: .top, spacing: 8) {
			Image(systemName: "exclamationmark.triangle.fill")
				.font(.system(size: 12))
				.foregroundStyle(.orange)
				.padding(.top, 1)
			Text("AI-generated content can contain errors. Treat answers as a starting point and verify with additional research before accepting them as fact.")
				.font(.system(size: 11))
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(10)
		.background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
	}

	private var scoreCard: some View {
		VStack(spacing: 10) {
			Text("Quiz Complete")
				.font(.system(size: 14, weight: .semibold))

			Text("\(correctCount) / \(questions.count)")
				.font(.system(size: 32, weight: .bold, design: .rounded))
				.foregroundStyle(scoreColor)

			Text("\(scorePercentage)%")
				.font(.system(size: 14, weight: .medium))
				.foregroundStyle(scoreColor)

			Text(scoreMessage)
				.font(.system(size: 12))
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity)
		.padding(16)
		.background(scoreColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
	}

	private var scorePercentage: Int {
		questions.isEmpty ? 0 : Int(Double(correctCount) / Double(questions.count) * 100)
	}

	private var scoreColor: Color {
		switch scorePercentage {
		case 80...: return .green
		case 60...: return .orange
		default:    return .red
		}
	}

	private var scoreMessage: String {
		switch scorePercentage {
		case 90...: return "Excellent comprehension!"
		case 80...: return "Great work — strong understanding."
		case 60...: return "Good effort — review the article for the missed points."
		default:    return "Keep reading — try reviewing the article and retake."
		}
	}

	private func checkAndSave() {
		guard isComplete, !scoreSaved else { return }
		scoreSaved = true
		onScoreSaved(correctCount, questions.count)
	}
}

// MARK: - Question card

private struct QuizQuestionCard: View {
	let index: Int
	let question: QuizQuestion
	let selectedAnswer: Int?
	let onSelect: (Int) -> Void

	private var isAnswered: Bool { selectedAnswer != nil }

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			// Question number + text
			HStack(alignment: .top, spacing: 6) {
				Text("\(index + 1).")
					.font(.system(size: 12, weight: .bold))
					.foregroundStyle(Color.accentColor)
					.frame(width: 18, alignment: .leading)
				Text(question.question)
					.font(.system(size: 13, weight: .medium))
					.fixedSize(horizontal: false, vertical: true)
			}

			// Answer options
			VStack(alignment: .leading, spacing: 6) {
				ForEach(Array(question.options.enumerated()), id: \.offset) { optIndex, option in
					AnswerOptionRow(
						label: optionLabel(optIndex),
						text: option,
						state: optionState(optIndex),
						onTap: { onSelect(optIndex) }
					)
				}
			}

			// Explanation (revealed after answering)
			if isAnswered {
				HStack(alignment: .top, spacing: 6) {
					Image(systemName: "lightbulb.fill")
						.font(.system(size: 10))
						.foregroundStyle(.yellow)
						.padding(.top, 2)
					Text(question.explanation)
						.font(.system(size: 11))
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
				.padding(8)
				.background(Color.yellow.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
			}
		}
		.padding(12)
		.background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
	}

	private func optionLabel(_ i: Int) -> String {
		question.type == .trueOrFalse ? "" : ["A", "B", "C", "D"][safe: i] ?? ""
	}

	private func optionState(_ i: Int) -> AnswerOptionState {
		guard let chosen = selectedAnswer else { return .idle }
		if i == question.correctIndex { return .correct }
		if i == chosen { return .wrong }
		return .idle
	}
}

// MARK: - Answer option row

private enum AnswerOptionState { case idle, correct, wrong }

private struct AnswerOptionRow: View {
	let label: String
	let text: String
	let state: AnswerOptionState
	let onTap: () -> Void

	private var bgColor: Color {
		switch state {
		case .idle:    return Color.secondary.opacity(0.08)
		case .correct: return Color.green.opacity(0.15)
		case .wrong:   return Color.red.opacity(0.15)
		}
	}

	private var borderColor: Color {
		switch state {
		case .idle:    return Color.clear
		case .correct: return Color.green.opacity(0.5)
		case .wrong:   return Color.red.opacity(0.5)
		}
	}

	private var icon: String? {
		switch state {
		case .idle:    return nil
		case .correct: return "checkmark.circle.fill"
		case .wrong:   return "xmark.circle.fill"
		}
	}

	var body: some View {
		Button(action: onTap) {
			HStack(spacing: 8) {
				if !label.isEmpty {
					Text(label)
						.font(.system(size: 11, weight: .bold))
						.foregroundStyle(state == .idle ? Color.accentColor : .secondary)
						.frame(width: 16)
				}
				Text(text)
					.font(.system(size: 12))
					.foregroundStyle(.primary)
					.fixedSize(horizontal: false, vertical: true)
					.multilineTextAlignment(.leading)
				Spacer(minLength: 4)
				if let icon {
					Image(systemName: icon)
						.font(.system(size: 13))
						.foregroundStyle(state == .correct ? Color.green : Color.red)
				}
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 7)
			.background(bgColor, in: RoundedRectangle(cornerRadius: 7))
			.overlay(
				RoundedRectangle(cornerRadius: 7)
					.strokeBorder(borderColor, lineWidth: 1)
			)
		}
		.buttonStyle(.plain)
		.disabled(state != .idle)
	}
}

// MARK: - Safe array subscript

private extension Array {
	subscript(safe index: Index) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}
