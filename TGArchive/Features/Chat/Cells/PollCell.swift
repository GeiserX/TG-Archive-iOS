import SwiftUI

/// A poll in the newest state the archive kept: the question, each answer with its share of the votes, the
/// number of voters, and "Closed" once it closed.
struct PollCell: View {
    let poll: Poll?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(LocalizedStringKey(poll?.quiz == true ? "chat.poll.quiz" : "preview.kind.poll"))
            } icon: {
                Image(systemName: "chart.bar.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            if let question = poll?.question?.nonBlank {
                Text(verbatim: question)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(poll?.rows ?? []) { row in
                PollRowView(row: row)
            }
            HStack(spacing: 6) {
                if let voters = poll?.results?.totalVoters {
                    Text("chat.poll.voters \(voters)")
                }
                if poll?.multipleChoice == true {
                    Text(verbatim: "·")
                    Text("chat.poll.multiple")
                }
                if poll?.closed == true {
                    Text(verbatim: "·")
                    Text("chat.poll.closed")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(width: MediaFrame.width, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct PollRowView: View {
    let row: PollRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: row.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if row.isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel(Text("chat.poll.correct"))
                }
                Spacer(minLength: 8)
                if row.voters != nil {
                    Text(row.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: row.fraction)
                .tint(.accentColor)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
