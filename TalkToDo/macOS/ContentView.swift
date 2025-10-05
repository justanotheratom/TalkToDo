import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("TalkToDo")
                .font(.largeTitle)
                .padding()

            Text("Phase 1: Project Setup Complete")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

#Preview {
    ContentView()
}
