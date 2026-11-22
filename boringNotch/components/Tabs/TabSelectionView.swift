//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Workflow", icon: "bolt.horizontal.circle.fill", view: .workflow)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var workflowStore = WorkflowStore.shared
    @Default(.boringShelf) private var boringShelf
    @Default(.showWorkflowTab) private var showWorkflowTab
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .overlay(alignment: .topTrailing) {
                        if tab.view == .workflow && workflowStore.needsYouCount > 0 {
                            Text("\(workflowStore.needsYouCount)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(Capsule().fill(Color.red))
                                .offset(x: -4, y: 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }

    /// Shelf nur bei aktiver Shelf-Funktion, Workflow nur bei aktiviertem Workflow-Tab.
    private var visibleTabs: [TabModel] {
        tabs.filter { tab in
            switch tab.view {
            case .home:
                return true
            case .shelf:
                return boringShelf
            case .workflow:
                return showWorkflowTab
            }
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
