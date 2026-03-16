//
//  SessionOperationGuideOverlayView.swift
//  SplitLog
//
//  Created by Codex on 2026/03/16.
//

import SwiftUI

struct SessionOperationGuideOverlayView: View {
    private struct GuideSection: Identifiable {
        let id: String
        let title: String
        let summary: String
        let details: [String]
    }

    private static let sections: [GuideSection] = [
        .init(
            id: "measure",
            title: "計測を進める",
            summary: "開始・Split・停止・再開の流れ",
            details: [
                "メインボタンで開始、停止、再開を切り替えます。",
                "Split ボタンで現在の作業区切りを閉じて、次の Split を作れます。",
                "停止中に再開すると、同じセッションを続きから計測します。"
            ]
        ),
        .init(
            id: "sessions",
            title: "セッションを切り替える",
            summary: "日ごとや作業単位で計測先を分ける",
            details: [
                "上部のセッション一覧から、今計測したいセッションへ切り替えられます。",
                "プラスボタンで新しいセッションを追加できます。",
                "不要なセッションは削除、現在の内容だけリセットも可能です。"
            ]
        ),
        .init(
            id: "split-mode",
            title: "Split を選ぶ",
            summary: "ラジオ配分とチェック配分を切り替える",
            details: [
                "ラジオ配分では、選択中の Split へ時間が入ります。",
                "チェック配分では、チェックが付いた Split 群へ時間を分配できます。",
                "モード切替はサマリーボタン左のアイコンから行えます。"
            ]
        ),
        .init(
            id: "memo-summary",
            title: "メモとサマリーを使う",
            summary: "Split ごとのメモと全体サマリーを確認",
            details: [
                "各 Split のメモアイコンから内容を記録できます。",
                "サマリーボタンで、セッション全体の一覧テキストを確認できます。",
                "サマリーはコピーできるので、日報や振り返りへ流用しやすいです。",
                "お問い合わせは案内や設定から開けて、そのままメール送信画面へ進めます。"
            ]
        ),
        .init(
            id: "shortcuts",
            title: "ショートカットを使う",
            summary: "Popover を開かずに主要操作を実行",
            details: [
                "⌘⌃S: Split / ⌘⌃X: 停止 / ⌘⌃R: 再開",
                "⌘⌃V: Popover の表示切替 / ⌘⌃M: 現在選択中 Split のメモを開く",
                "⌘⌃1...9 / 0 / ↑↓ で Split 選択や移動も行えます。"
            ]
        ),
        .init(
            id: "settings",
            title: "表示や初期値を整える",
            summary: "テーマ、リング周期、初期モード、ロックなどの調整",
            details: [
                "設定からテーマカラーやリング周期を変更できます。",
                "新規セッションのデフォルト配分モードも設定できます。",
                "円グラフ左上の小さい表示からもリング周期の設定を開けます。",
                "タイトル右の南京錠アイコンをオンにすると、Popover 外をクリックしても閉じなくなります。",
                "サマリーの表示形式やストレージ初期化もここから行います。"
            ]
        )
    ]

    let onClose: () -> Void
    @State private var expandedSectionID: GuideSection.ID? = sections.first?.id

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("操作説明")
                            .font(.headline)
                        Text("SplitLog でできることを順番に確認できます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("閉じる")
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Self.sections) { section in
                            guideSectionRow(section)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 278)
            }
            .padding(16)
            .frame(width: 408)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
        }
    }

    private func guideSectionRow(_ section: GuideSection) -> some View {
        let isExpanded = expandedSectionID == section.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expandedSectionID = isExpanded ? nil : section.id
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(section.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.78))
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(section.details, id: \.self) { detail in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.accentColor.opacity(0.85))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(detail)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.62))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isExpanded ? Color.black.opacity(0.035) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isExpanded ? Color.primary.opacity(0.08) : Color.clear, lineWidth: 1)
        )
    }
}
