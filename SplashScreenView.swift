import SwiftUI

struct SplashScreenView: View {
    @State private var startApp = false
    @State private var loadingProgress: CGFloat = 0.0

    var body: some View {
        if startApp {
            ContentView() // This calls your existing code
        } else {
            ZStack {
                Color(red: 240/255, green: 240/255, blue: 240/255)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Logo/Icon
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.orange)
                    
                    VStack(spacing: 8) {
                        Text("MUSEUM EXPLORER")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .tracking(2)
                        
                        Text("Smart Wayfinding")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Loading Bar
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 200, height: 6)
                        
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange)
                            .frame(width: 200 * loadingProgress, height: 6)
                    }
                }
            }
            .onAppear {
                // Animate the loading bar
                withAnimation(.linear(duration: 2.0)) {
                    loadingProgress = 1.0
                }
                // Transition to main app
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        startApp = true
                    }
                }
            }
        }
    }
}
