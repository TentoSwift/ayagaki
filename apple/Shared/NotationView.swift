import SwiftUI

/// 交換記号の表（値ベース）。エディタでも PDF 手順書でも使う。
struct NotationTable: View {
    var groups: [NotationGroup]
    var selected: ClosedRange<Int>? = nil
    var onTap: ((NotationGroup) -> Void)? = nil
    /// 左右の記号セルをタップしたとき（⬆ の切り替え）。nil なら行全体タップ＝onTap
    var onToggleArrow: ((NotationGroup, BraidSide) -> Void)? = nil

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
                        .contentShape(Rectangle())
                        .onTapGesture { onTap?(g) }
                    notationCell(g.left, side: .left, group: g)
                    notationCell(g.right, side: .right, group: g)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(isSelected ? Color.red.opacity(0.12) : Color.clear)
                Divider()
            }
        }
    }

    /// 記号テキスト。⬆ は中央で上ル段だけに表示され、タップで切り替え
    @ViewBuilder
    private func notationCell(_ text: String, side: BraidSide, group: NotationGroup) -> some View {
        if let onToggleArrow {
            Text(text)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onToggleArrow(group, side) }
                .help("タップで ⬆（中央で上ル）を切り替え")
        } else {
            Text(text)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            } : nil,
            onToggleArrow: interactive ? { g, side in
                vm.toggleArrows(g.from...g.to, side: side)
            } : nil)
    }
}
