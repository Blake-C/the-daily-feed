import SwiftUI

struct QuizStatsView: View {
	@ObservedObject var vm: QuizStatsViewModel

	var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 0) {
				// Header
				VStack(alignment: .leading, spacing: 4) {
					Text("Quiz Stats")
						.font(.system(size: 22, weight: .bold, design: .serif))
					Text("Your comprehension scores over time")
						.font(.system(size: 12))
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 24)
				.padding(.top, 20)
				.padding(.bottom, 16)

				if vm.yearStats.quizCount == 0 {
					ContentUnavailableView(
						"No Quizzes Yet",
						systemImage: "brain.head.profile",
						description: Text("Open an article and tap \"Test Your Knowledge\" to take your first quiz.")
					)
					.padding(.top, 40)
				} else {
					// Period summary cards
					HStack(spacing: 12) {
						PeriodStatCard(label: "Today",      stats: vm.todayStats)
						PeriodStatCard(label: "This Month", stats: vm.monthStats)
						PeriodStatCard(label: "This Year",  stats: vm.yearStats)
					}
					.padding(.horizontal, 24)
					.padding(.bottom, 20)

					// Recent results
					VStack(alignment: .leading, spacing: 4) {
						Text("Recent Quizzes")
							.font(.system(size: 14, weight: .semibold))
							.padding(.horizontal, 24)
							.padding(.bottom, 6)

						VStack(spacing: 8) {
							ForEach(vm.recentResults) { result in
								QuizResultRow(result: result)
							}
						}
						.padding(.horizontal, 24)
					}
					.padding(.bottom, 32)
				}
			}
		}
		.onAppear { vm.load() }
	}
}

// MARK: - Period stat card

private struct PeriodStatCard: View {
	let label: String
	let stats: QuizPeriodStats

	private var percentageColor: Color {
		guard stats.total > 0 else { return .secondary }
		switch stats.percentage {
		case 80...: return .green
		case 60...: return .orange
		default:    return .red
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(label)
				.font(.system(size: 11, weight: .semibold))
				.foregroundStyle(.secondary)
				.textCase(.uppercase)

			if stats.total > 0 {
				Text("\(stats.percentage)%")
					.font(.system(size: 26, weight: .bold, design: .rounded))
					.foregroundStyle(percentageColor)

				Text("\(stats.correct)/\(stats.total) correct")
					.font(.system(size: 12))
					.foregroundStyle(.secondary)

				Text("\(stats.quizCount) quiz\(stats.quizCount == 1 ? "" : "zes")")
					.font(.system(size: 11))
					.foregroundStyle(.tertiary)
			} else {
				Text("—")
					.font(.system(size: 22, weight: .bold))
					.foregroundStyle(.tertiary)
				Text("No quizzes")
					.font(.system(size: 12))
					.foregroundStyle(.tertiary)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
	}
}

// MARK: - Result row

private struct QuizResultRow: View {
	let result: QuizResult

	private var percentageColor: Color {
		switch result.percentage {
		case 80...: return .green
		case 60...: return .orange
		default:    return .red
		}
	}

	var body: some View {
		HStack(spacing: 12) {
			// Score badge
			Text("\(result.percentage)%")
				.font(.system(size: 13, weight: .bold, design: .rounded))
				.foregroundStyle(percentageColor)
				.frame(width: 46, alignment: .trailing)
				.monospacedDigit()

			VStack(alignment: .leading, spacing: 2) {
				Text(result.articleTitle)
					.font(.system(size: 13, weight: .medium))
					.lineLimit(1)
				HStack(spacing: 4) {
					Text("\(result.score)/\(result.totalQuestions) correct")
						.font(.system(size: 11))
						.foregroundStyle(.secondary)
					Text("·")
						.foregroundStyle(.quaternary)
						.font(.system(size: 11))
					Text(result.completedAt, style: .date)
						.font(.system(size: 11))
						.foregroundStyle(.tertiary)
				}
			}

			Spacer(minLength: 0)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
	}
}
