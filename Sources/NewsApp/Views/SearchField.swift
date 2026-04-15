import SwiftUI

struct SearchField: View {
	@Binding var text: String

	var body: some View {
		HStack(spacing: 6) {
			Image(systemName: "magnifyingglass")
				.foregroundStyle(.secondary)
				.font(.system(size: 13))

			TextField("Search title, author, body…", text: $text)
				.textFieldStyle(.plain)
				.font(.system(size: 13))
				.help("Searches article title, author, summary, and full extracted text")

			if !text.isEmpty {
				Button {
					text = ""
				} label: {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(.secondary)
						.font(.system(size: 12))
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 5)
		.background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
	}
}
