import SwiftUI

struct RoleSelectionView: View {
    @ObservedObject var session: SessionModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("REC:ON")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                    Text("두 기기를 한 촬영 시스템으로 연결합니다")
                        .foregroundStyle(.secondary)
                    Text("같은 Wi-Fi에서 Camera를 먼저 선택한 뒤, 다른 기기에서 Monitor를 선택하세요")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                }

                HStack(spacing: 16) {
                    ForEach(DeviceRole.allCases) { role in
                        Button {
                            session.send(.selectRole(role))
                        } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                Image(systemName: role == .camera ? "camera.fill" : "rectangle.inset.filled.and.person.filled")
                                    .font(.system(size: 32))
                                Text(role.title)
                                    .font(.title2.bold())
                                Text(role.subtitle)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                            .padding(24)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 760)
        }
    }
}
