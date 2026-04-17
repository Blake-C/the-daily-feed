import AppKit
import SwiftUI

struct ArticleQuizView: View {
	let questions: [QuizQuestion]
	let isLoading: Bool
	var statusMessage: String? = nil
	let disputeResults: [Int: QuizDisputeResult]
	let disputingIndices: Set<Int>
	let onClose: () -> Void
	let onRegenerate: () -> Void
	var onScrollToParagraph: ((String, Int) -> Void)? = nil
	let onDispute: (Int, Int) async -> Void
	let onScoreSaved: (Int, Int) -> Void

	@State private var selectedAnswers: [Int: Int] = [:]
	@State private var scoreSaved = false

	private var isComplete: Bool { selectedAnswers.count == questions.count && !questions.isEmpty }

	private var correctCount: Int {
		selectedAnswers.reduce(0) { sum, pair in
			let effectiveCorrect = disputeResults[pair.key]?.correctedAnswerIndex ?? questions[pair.key].correctIndex
			return sum + (effectiveCorrect == pair.value ? 1 : 0)
		}
	}

	private var disputeBonusCount: Int {
		disputeResults.values.filter { $0.userIsCorrect }.count
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			// Panel header
			HStack {
				Label("Test Your Knowledge", systemImage: "brain.head.profile")
					.font(.system(size: 13, weight: .semibold))
				Spacer()
				Button(action: onRegenerate) {
					Image(systemName: "arrow.clockwise")
						.font(.system(size: 13))
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
				.disabled(isLoading)
				.help("Regenerate quiz questions")
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
					if isLoading && questions.isEmpty {
						VStack(spacing: 10) {
							ProgressView().scaleEffect(0.8)
							Text(statusMessage ?? "Generating questions…")
								.font(.system(size: 13))
								.foregroundStyle(.secondary)
								.multilineTextAlignment(.center)
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
								disputeResult: disputeResults[index],
								isDisputing: disputingIndices.contains(index),
								onSelect: { chosen in
									guard selectedAnswers[index] == nil else { return }
									selectedAnswers[index] = chosen
									if let hint = question.paragraphHint, !hint.isEmpty {
										onScrollToParagraph?(hint, index + 1)
									}
									checkAndSave()
								},
								onDispute: {
									guard let chosen = selectedAnswers[index] else { return }
									Task { await onDispute(index, chosen) }
								}
							)
						}

						if isLoading {
							HStack(spacing: 8) {
								ProgressView().scaleEffect(0.7)
								Text(statusMessage ?? "Generating questions…")
									.font(.system(size: 11))
									.foregroundStyle(.secondary)
							}
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.horizontal, 4)
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
				.textSelection(.enabled)
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

			if disputeBonusCount > 0 {
				Text("Includes +\(disputeBonusCount) from successful dispute\(disputeBonusCount > 1 ? "s" : "")")
					.font(.system(size: 11))
					.foregroundStyle(.secondary)
			}

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
	let disputeResult: QuizDisputeResult?
	let isDisputing: Bool
	let onSelect: (Int) -> Void
	let onDispute: () -> Void

	private var isAnswered: Bool { selectedAnswer != nil }

	private var effectiveCorrectIndex: Int {
		disputeResult?.correctedAnswerIndex ?? question.correctIndex
	}

	private var userWasWrong: Bool {
		guard let chosen = selectedAnswer else { return false }
		return chosen != question.correctIndex
	}

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
					.textSelection(.enabled)
			}

			// Answer options
			VStack(alignment: .leading, spacing: 6) {
				ForEach(Array(question.options.enumerated()), id: \.offset) { optIndex, option in
					AnswerOptionRow(
						label: optionLabel(optIndex),
						text: stripOptionPrefix(option),
						state: optionState(optIndex),
						onTap: { onSelect(optIndex) }
					)
				}
			}

			// Explanation area (revealed after answering)
			if isAnswered {
				let explanation = disputeResult?.explanation ?? question.explanation
				HStack(alignment: .top, spacing: 6) {
					Image(systemName: "lightbulb.fill")
						.font(.system(size: 10))
						.foregroundStyle(.secondary)
						.padding(.top, 2)
					Text(explanation)
						.font(.system(size: 11))
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
						.textSelection(.enabled)
				}
				.padding(8)
				.background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

				// Dispute area
				disputeArea
			}
		}
		.padding(12)
		.background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
	}

	@ViewBuilder
	private var disputeArea: some View {
		if let result = disputeResult {
			// Result returned — show verdict banner
			HStack(alignment: .top, spacing: 8) {
				Image(systemName: result.userIsCorrect ? "checkmark.seal.fill" : "checkmark.circle")
					.font(.system(size: 12))
					.foregroundStyle(result.userIsCorrect ? Color.green : Color.secondary)
					.padding(.top, 1)
				VStack(alignment: .leading, spacing: 3) {
					Text(result.userIsCorrect
						 ? "You were right — we apologise!"
						 : "Original answer confirmed")
						.font(.system(size: 11, weight: .semibold))
						.foregroundStyle(result.userIsCorrect ? Color.green : Color.secondary)
					if result.userIsCorrect {
						Text("Your answer has been accepted and your score updated.")
							.font(.system(size: 11))
							.foregroundStyle(.secondary)
					}
				}
			}
			.padding(8)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(
				(result.userIsCorrect ? Color.green : Color.secondary).opacity(0.08),
				in: RoundedRectangle(cornerRadius: 6)
			)
		} else if isDisputing {
			// Ollama review in progress
			HStack(spacing: 8) {
				ProgressView().scaleEffect(0.75)
				Text("Reviewing with Ollama…")
					.font(.system(size: 11))
					.foregroundStyle(.secondary)
			}
			.padding(8)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
		} else if userWasWrong {
			// Offer dispute button
			Button(action: onDispute) {
				Label("Dispute this answer", systemImage: "flag")
					.font(.system(size: 11))
			}
			.buttonStyle(.bordered)
			.controlSize(.mini)
			.help("Ask Ollama to re-examine this question")
		}
	}

	private func optionLabel(_ i: Int) -> String {
		question.type == .trueOrFalse ? "" : ["A", "B", "C", "D"][safe: i] ?? ""
	}

	private func optionState(_ i: Int) -> AnswerOptionState {
		guard let chosen = selectedAnswer else { return .idle }
		if i == effectiveCorrectIndex { return .correct }
		if i == chosen { return .wrong }
		return .dimmed
	}

	// Strip "A. ", "A) ", "A: ", "(A) ", "1. ", "1) " prefixes the model sometimes adds.
	private func stripOptionPrefix(_ text: String) -> String {
		let t = text.trimmingCharacters(in: .whitespaces)
		let patterns = [
			#"^[A-Da-d]\.\s+"#,
			#"^[A-Da-d]\)\s+"#,
			#"^[A-Da-d]:\s+"#,
			#"^\([A-Da-d]\)\s*"#,
			#"^\d+\.\s+"#,
			#"^\d+\)\s+"#,
		]
		for pattern in patterns {
			if let range = t.range(of: pattern, options: .regularExpression) {
				let stripped = String(t[range.upperBound...]).trimmingCharacters(in: .whitespaces)
				if !stripped.isEmpty { return stripped }
			}
		}
		return t
	}
}

// MARK: - Answer option row

private enum AnswerOptionState { case idle, correct, wrong, dimmed }

private struct AnswerOptionRow: View {
	let label: String
	let text: String
	let state: AnswerOptionState
	let onTap: () -> Void

	private var bgColor: Color {
		switch state {
		case .idle:    return Color.secondary.opacity(0.08)
		case .correct: return Color.green.opacity(0.22)
		case .wrong:   return Color.red.opacity(0.22)
		case .dimmed:  return Color.secondary.opacity(0.04)
		}
	}

	private var borderColor: Color {
		switch state {
		case .idle:    return Color.clear
		case .correct: return Color.green.opacity(0.75)
		case .wrong:   return Color.red.opacity(0.75)
		case .dimmed:  return Color.clear
		}
	}

	private var labelColor: Color {
		switch state {
		case .idle:    return Color.accentColor
		case .correct: return Color.green
		case .wrong:   return Color.red
		case .dimmed:  return Color.secondary.opacity(0.5)
		}
	}

	private var icon: String? {
		switch state {
		case .correct: return "checkmark.circle.fill"
		case .wrong:   return "xmark.circle.fill"
		default:       return nil
		}
	}

	var body: some View {
		Button(action: onTap) {
			HStack(spacing: 8) {
				if !label.isEmpty {
					Text(label)
						.font(.system(size: 11, weight: .bold))
						.foregroundStyle(labelColor)
						.frame(width: 16)
				}
				Text(text)
					.font(.system(size: 12))
					.foregroundStyle(state == .dimmed ? Color.secondary : Color.primary)
					.fixedSize(horizontal: false, vertical: true)
					.multilineTextAlignment(.leading)
					.textSelection(.enabled)
				Spacer(minLength: 4)
				if let icon {
					Image(systemName: icon)
						.font(.system(size: 14, weight: .semibold))
						.foregroundStyle(state == .correct ? Color.green : Color.red)
				}
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 7)
			.background(bgColor, in: RoundedRectangle(cornerRadius: 7))
			.overlay(
				RoundedRectangle(cornerRadius: 7)
					.strokeBorder(borderColor, lineWidth: 1.5)
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
