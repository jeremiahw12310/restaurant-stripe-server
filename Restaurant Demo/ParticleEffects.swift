import SwiftUI
import UIKit
import Combine

// MARK: - Gold Sparkles Particle System
struct GoldSparklesView: View {
    @State private var particles: [SparkleParticle] = []
    @State private var timer: Timer?
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var cancellable: AnyCancellable?
    
    let maxParticles = 30 // Performance budget
    let isActive: Bool
    
    init(isActive: Bool = true) {
        self.isActive = isActive
    }
    
    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 1.0, green: 0.8, blue: 0.0).opacity(particle.opacity),
                                Color(red: 0.95, green: 0.85, blue: 0.7).opacity(particle.opacity * 0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: particle.size, height: particle.size)
                    .blur(radius: particle.blur)
                    .position(x: particle.x, y: particle.y)
                    .animation(.easeInOut(duration: particle.animationDuration), value: particle.x)
                    .animation(.easeInOut(duration: particle.animationDuration), value: particle.y)
                    .animation(.easeInOut(duration: particle.animationDuration), value: particle.opacity)
            }
        }
        .onAppear {
            if isActive && shouldRunEffects {
                startSparkleAnimation()
            }
            // Observe Low Power Mode changes
            cancellable = NotificationCenter.default
                .publisher(for: .NSProcessInfoPowerStateDidChange)
                .sink { _ in
                    isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                    handleStateChange()
                }
        }
        .onDisappear {
            stopSparkleAnimation()
            cancellable?.cancel()
            cancellable = nil
        }
        .onChange(of: isActive) { newValue in
            handleStateChange()
        }
        .onChange(of: scenePhase) { _ in
            handleStateChange()
        }
    }
    
    private var shouldRunEffects: Bool {
        return !isLowPowerMode && scenePhase == .active
    }
    
    private func startSparkleAnimation() {
        // Only start if not already running
        guard timer == nil else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            // Remove old particles
            particles.removeAll { $0.opacity <= 0.1 }
            
            // Add new particle if under budget
            if particles.count < maxParticles {
                addSparkleParticle()
            }
            
            // Update existing particles
            updateParticles()
        }
    }
    
    private func stopSparkleAnimation() {
        timer?.invalidate()
        timer = nil
        particles.removeAll()
    }

    private func handleStateChange() {
        if isActive && shouldRunEffects {
            startSparkleAnimation()
        } else {
            stopSparkleAnimation()
        }
    }
    
    private func addSparkleParticle() {
        let screenBounds = UIScreen.main.bounds
        let particle = SparkleParticle(
            x: CGFloat.random(in: 50...(screenBounds.width - 50)),
            y: CGFloat.random(in: 100...(screenBounds.height - 200)),
            size: CGFloat.random(in: 3...8),
            opacity: Double.random(in: 0.6...1.0),
            blur: CGFloat.random(in: 0.5...2.0),
            animationDuration: Double.random(in: 2.0...4.0)
        )
        particles.append(particle)
    }
    
    private func updateParticles() {
        for i in 0..<particles.count {
            particles[i].opacity *= 0.98
            particles[i].y -= CGFloat.random(in: 0.5...2.0)
            particles[i].x += CGFloat.random(in: -1.0...1.0)
        }
    }
}

struct SparkleParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    let size: CGFloat
    var opacity: Double
    let blur: CGFloat
    let animationDuration: Double
} 