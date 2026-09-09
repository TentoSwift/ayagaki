import SwiftUI

/// 交換記号の表（値ベース）。エディタでも PDF 手順書でも使う。
struct NotationTable: View {
    var groups: [NotationGroup]
    var selected: ClosedRange<Int>? = nil
    var onTap: ((NotationGroup) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ForEach(groups) { g in
                let isSelected = selected == g.from...g.to
                HStack(alignment: .top, spacing: 8) {
                    Text(g.label)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 56, alignment: .leading)
                    notationCell(g.left)
                    notationCell(g.right)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(isSelected ? Color.red.opacity(0.12) : Color.clear)
                // 段をタップすると選択され、手取り図がその段に切り替わる（記号表自体は読み取り専用）
                .contentShape(Rectangle())
                .onTapGesture { onTap?(g) }
                Divider()
            }
        }
    }

    /// 記号テキスト（読み取り専用）。⬆ は中央の色（d=0）から自動導出される
    private func notationCell(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("段").frame(width: 56, alignment: .leading)
            Text("左半面").frame(maxWidth: .infinity, alignment: .leading)
            Text("右半面").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.bold))
        .foregroundColor(.secondary)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }
}

/// エディタ用ラッパ。タップで該当段をグリッド上でハイライトする。
struct NotationView: View {
    @ObservedObject var vm: EditorViewModel
    var interactive = true

    var body: some View {
        NotationTable(
            groups: vm.notationGroups,
            selected: interactive ? vm.highlighted : nil,
            onTap: interactive ? { g in
                let range = g.from...g.to
                vm.highlighted = (vm.highlighted == range) ? nil : range
            } : nil)
    }
}
