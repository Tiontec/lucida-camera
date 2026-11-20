import UIKit

// 设置页的小部件：卡片、行。所有「玻璃 / 平面」背景统一走 DualBackdrop.apply(glass:flat:)，不自己写死半透明色和模糊。

/// 圆角卡片：里面一行一行，行与行之间有分割线
final class SettingsCard: UIView {
    private let stack = UIStackView()

    init(glass: Bool) {
        super.init(frame: .zero)
        layer.cornerRadius = 18; layer.cornerCurve = .continuous; clipsToBounds = true
        let back = DualBackdrop(radius: 18)
        back.translatesAutoresizingMaskIntoConstraints = false
        back.apply(glass: glass, flat: UIColor(white: 1, alpha: 0.08))
        addSubview(back)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: topAnchor), back.bottomAnchor.constraint(equalTo: bottomAnchor),
            back.leadingAnchor.constraint(equalTo: leadingAnchor), back.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor)])
    }
    required init?(coder: NSCoder) { fatalError() }

    func addRow(_ v: UIView) {
        if !stack.arrangedSubviews.isEmpty { stack.addArrangedSubview(SettingsCard.divider()) }
        stack.addArrangedSubview(v)
    }

    private static func divider() -> UIView {
        let box = UIView()
        let line = UIView()
        line.backgroundColor = UIColor(white: 1, alpha: 0.10)
        line.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(line)
        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            line.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5)])
        return box
    }
}

/// 设置里的一行：左边 标题 + 说明，右边 当前值 + 附件（开关 / 对勾 / 箭头）。整行可点（有附件开关的行除外）
final class SettingsRowView: UIControl {
    var onTap: (() -> Void)?
    let titleL = UILabel()
    let subL = UILabel()
    let valueL = UILabel()

    init(title: String, sub: String = "", value: String = "", accessory: UIView? = nil, interactiveAccessory: Bool = false) {
        super.init(frame: .zero)
        titleL.text = title; titleL.textColor = .white; titleL.font = .systemFont(ofSize: 16); titleL.numberOfLines = 0
        subL.text = sub; subL.textColor = UIColor(white: 1, alpha: 0.5); subL.font = .systemFont(ofSize: 12.5); subL.numberOfLines = 0
        subL.isHidden = sub.isEmpty
        valueL.text = value; valueL.textColor = UIColor(white: 1, alpha: 0.55); valueL.font = .systemFont(ofSize: 15)
        valueL.isHidden = value.isEmpty
        valueL.setContentHuggingPriority(.required, for: .horizontal)
        valueL.setContentCompressionResistancePriority(.required, for: .horizontal)

        let left = UIStackView(arrangedSubviews: [titleL, subL])
        left.axis = .vertical; left.spacing = 3
        left.isUserInteractionEnabled = false

        var rv: [UIView] = [valueL]
        if let a = accessory {
            a.setContentHuggingPriority(.required, for: .horizontal)
            a.setContentCompressionResistancePriority(.required, for: .horizontal)
            rv.append(a)
        }
        let right = UIStackView(arrangedSubviews: rv)
        right.axis = .horizontal; right.spacing = 8; right.alignment = .center
        right.setContentHuggingPriority(.required, for: .horizontal)
        right.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [left, right])
        row.axis = .horizontal; row.spacing = 12; row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        if !interactiveAccessory { row.isUserInteractionEnabled = false }   // 整行交给 UIControl 自己处理点击
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 54)])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() { onTap?() }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted && onTap != nil ? UIColor(white: 1, alpha: 0.08) : .clear }
    }
}

/// 一行里放控件在下面（分段选择 / 滑条）：标题 + 说明 + 控件
final class SettingsControlRow: UIView {
    init(title: String, sub: String, value: String = "", control: UIView) {
        super.init(frame: .zero)
        let t = UILabel(); t.text = title; t.textColor = .white; t.font = .systemFont(ofSize: 16); t.numberOfLines = 0
        let v = UILabel(); v.text = value; v.textColor = UIColor(white: 1, alpha: 0.55); v.font = .systemFont(ofSize: 15)
        v.isHidden = value.isEmpty
        v.setContentHuggingPriority(.required, for: .horizontal)
        let top = UIStackView(arrangedSubviews: [t, v]); top.axis = .horizontal; top.alignment = .firstBaseline; top.spacing = 8
        var parts: [UIView] = [top]
        if !sub.isEmpty {
            let s = UILabel(); s.text = sub; s.textColor = UIColor(white: 1, alpha: 0.5); s.font = .systemFont(ofSize: 12.5); s.numberOfLines = 0
            parts.append(s)
        }
        parts.append(control)
        let col = UIStackView(arrangedSubviews: parts)
        col.axis = .vertical; col.spacing = 8
        col.setCustomSpacing(10, after: parts[parts.count - 2])
        col.translatesAutoresizingMaskIntoConstraints = false
        addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            col.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
            col.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            col.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// 文字小部件：黄色集合标题（后面拖一条细线）/ 灰色小标题 / 灰色说明
enum SettingsText {
    static func heading(_ text: String) -> UIView {
        let l = UILabel(); l.text = text; l.textColor = dualYellow; l.font = .systemFont(ofSize: 18, weight: .bold)
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        let line = UIView(); line.backgroundColor = dualYellow.withAlphaComponent(0.28)
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let h = UIStackView(arrangedSubviews: [l, line]); h.axis = .horizontal; h.alignment = .center; h.spacing = 12
        return pad(h, left: 6, right: 0)
    }

    static func subhead(_ text: String) -> UIView {
        let l = UILabel(); l.text = text; l.textColor = UIColor(white: 1, alpha: 0.55); l.font = .systemFont(ofSize: 14)
        return pad(l, left: 8, right: 8)
    }

    static func note(_ text: String) -> UIView {
        let l = UILabel(); l.text = text; l.textColor = UIColor(white: 1, alpha: 0.45); l.font = .systemFont(ofSize: 12.5); l.numberOfLines = 0
        return pad(l, left: 10, right: 10)
    }

    private static func pad(_ v: UIView, left: CGFloat, right: CGFloat) -> UIView {
        let box = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: box.topAnchor), v.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: left),
            v.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -right)])
        return box
    }
}
