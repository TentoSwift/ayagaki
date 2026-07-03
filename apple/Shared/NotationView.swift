import SwiftUI

/// 交換記号の一覧（段グループ化）。タップで該当段をグリッド上でハイライト。
struct NotationView: View {
    @ObservedObject var vm: EditorViewModel
    var interactive = true

    var body: some View {
        let groups = vm.notationGroups
        VStack(spacing: 0) {
            headerRow
            Divider()
            ForEach(groups) { g in
                let selected = interactive && vm.highlighted == g.from...g.to
                HStack(alignment: .top, spacing: 8) {
                    Text(g.label)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 56, alignment: .leading)
                    Text(g.left)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(g.right)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(selected ? Color.red.opacity(0.12) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard interactive else { return }
                    let range = g.from...g.to
                    vm.highlighted = (vm.highlighted == range) ? nil : range
                }
                Divider()
            }
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
