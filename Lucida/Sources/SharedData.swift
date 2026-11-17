// 由 shared/lucida-shared.json 生成（tools/gen_shared.py）——不要手改；改 json 再重新生成。网页 / iOS / 安卓共用同一份调色数据。
import Foundation

struct StylePreset {
    let sid: String, name: String, grp: String
    let t: Double, c: Double, s: Double          // 色调 / 颜色 / 强度（-100…100，强度 0…100）
    let cast: [Double], ca: Double
    let tintUI: [Double], tintUI2: [Double]?       // 主页面调色盘底图的配色
    var tint: [Double] { cast }                 // 预设顺序页的小圆点用
    var fade: Double = 0, con: Double = 0
}

enum SharedApp {
    static let version = "11.5.0"
    static let build = 33
}

enum SharedGrade {
    static let toneK: Double = 0.6, satK: Double = 0.8, fadeK: Double = 1
    static let texOn: Double = 0.004, grainOn: Double = 0.004, grainK: Double = 0.3
    /// 质感系数：行 = 标准 / 柔肤 / 光晕 / 胶片，列 = con sat hi sh tmp cl sp gr hal
    static let texKeys = ["con", "sat", "hi", "sh", "tmp", "cl", "sp", "gr", "hal"]
    static let texCoef: [[Double]] = [
        [0.06, 0.05, 0, 0, 0, 0.55, 0.9, 0, 0],
        [-0.06, -0.03, 0, 0.1, 0, -0.9, -1, 0, 0],
        [0, 0.05, -0.08, 0, 0, -0.5, 0, 0, 1.25],
        [0.14, -0.14, -0.12, 0, 0.05, 0, 0, 0.2, 0],
    ]
    static let texShd: [[Double]] = [[0, 0, 0], [0, 0, 0], [0, 0, 0], [-0.02, 0.014, 0.03]]
}

let texNames = ["标准", "柔肤", "光晕", "胶片"]

let stylePresets: [StylePreset] = [
    StylePreset(sid: "standard", name: "标准", grp: "底色", t: 0, c: 0, s: 100, cast: [1, 1, 1], ca: 0, tintUI: [0.38, 0.46, 0.62], tintUI2: nil),
    StylePreset(sid: "pearl", name: "珠光", grp: "底色", t: 18, c: 0, s: 100, cast: [1, 0.66, 0.76], ca: 0.28, tintUI: [0.62, 0.2, 0.3], tintUI2: nil, fade: 0.02),
    StylePreset(sid: "coolrose", name: "冷调玫瑰色", grp: "底色", t: -100, c: -100, s: 75, cast: [0.86, 0.7, 0.92], ca: 0.42, tintUI: [0.42, 0.5, 0.72], tintUI2: nil),
    StylePreset(sid: "amber", name: "琥珀色", grp: "底色", t: 20, c: 20, s: 100, cast: [1, 0.7, 0.3], ca: 0.55, tintUI: [0.72, 0.45, 0.2], tintUI2: nil),
    StylePreset(sid: "gold", name: "金色", grp: "底色", t: 20, c: 10, s: 85, cast: [1, 0.82, 0.3], ca: 0.5, tintUI: [0.85, 0.58, 0.08], tintUI2: nil),
    StylePreset(sid: "rosegold", name: "玫瑰金色", grp: "底色", t: -20, c: -20, s: 75, cast: [1, 0.72, 0.62], ca: 0.45, tintUI: [0.66, 0.4, 0.3], tintUI2: nil),
    StylePreset(sid: "natural", name: "自然", grp: "心情", t: -70, c: -15, s: 100, cast: [0.78, 0.84, 0.94], ca: 0.12, tintUI: [0.34, 0.4, 0.58], tintUI2: nil),
    StylePreset(sid: "cozy", name: "温馨", grp: "心情", t: -75, c: -20, s: 100, cast: [1, 0.72, 0.74], ca: 0.38, tintUI: [0.84, 0.42, 0.12], tintUI2: nil),
    StylePreset(sid: "calm", name: "安静", grp: "心情", t: 50, c: 45, s: 100, cast: [1, 0.9, 0.66], ca: 0.3, tintUI: [0.46, 0.6, 0.5], tintUI2: nil),
    StylePreset(sid: "ethereal", name: "缥缈", grp: "心情", t: 68, c: -15, s: 100, cast: [0.72, 0.78, 1], ca: 0.2, tintUI: [0.2, 0.42, 0.78], tintUI2: nil, fade: 0.06),
    StylePreset(sid: "contrast", name: "反差色", grp: "心情", t: -76, c: 19, s: 100, cast: [0.55, 0.82, 0.96], ca: 0.22, tintUI: [0.1, 0.55, 0.7], tintUI2: nil, con: 0.28),
    StylePreset(sid: "radiant", name: "耀目", grp: "心情", t: 35, c: 30, s: 100, cast: [0.88, 0.78, 1], ca: 0.22, tintUI: [0.3, 0.5, 0.72], tintUI2: nil),
    StylePreset(sid: "vivid", name: "鲜明", grp: "心情", t: -30, c: 33, s: 100, cast: [1, 1, 1], ca: 0, tintUI: [0.78, 0.2, 0.2], tintUI2: [0.1, 0.6, 0.55], con: 0.16)
]
