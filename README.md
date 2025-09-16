![AsyncCombine: Combine's Syntax](https://raw.githubusercontent.com/will-lumley/AsyncCombine/main/AsyncCombine.png)

# AsyncCombine

<p align="center">
    <img src="https://github.com/will-lumley/AsyncCombine/actions/workflows/macos-tests.yml/badge.svg?branch=main" alt="Apple - CI Status">
    <img src="https://github.com/will-lumley/AsyncCombine/actions/workflows/linux-tests.yml/badge.svg?branch=main" alt="Linux - CI Status">
</p>
<p align="center">
  <a href="https://github.com/apple/swift-package-manager"><img src="https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat" alt="SPM Compatible"></a>
  <img src="https://img.shields.io/badge/Swift-6.2-orange.svg" alt="Swift 6.2">
  <a href="https://bsky.app/profile/will-lumley.bsky.social">
    <img src="https://img.shields.io/badge/Bluesky-0285FF?logo=bluesky&logoColor=fff&label=will-lumley" alt="Bluesky">
  </a>
  <a href="https://mastodon.social/@wlumley">
    <img src="https://img.shields.io/badge/Mastodon-@wlumley-6364FF?logo=mastodon&logoColor=fff" alt="Mastodon">
  </a>
</p>

AsyncCombine brings familiar Combine-style operators like `sink`, `assign`, and `store(in:)` — to the world of Swift Concurrency.

While Swift Concurrency has certainly been an improvement over Combine when combined (heh) with swift-async-algorithms, managing multiple subscriptions can be quite a messy process.

Introducing, AsyncCombine! It’s built on top of `AsyncSequence` and integrated with Swift’s `Observation` framework, so you can react to `@Observable` model changes, bind values to UI, and manage state, all without importing Combine. Beacuse of this, it works on any platform that Swift runs on, from iOS and macOS to Linux and SwiftWasm.

It also ships with CurrentValueRelay, a replay-1 async primitive inspired by Combine’s `CurrentValueSubject`, giving you a simple way to bridge stateful streams between domain logic and presentation.

## ✨ Features

### 🔗 Combine-like Syntax
- Write familiar, declarative pipelines without pulling in Combine.
- Use `.sink {}` to respond to values from any `AsyncSequence`.
- Use `.assign(to:on:)` to bind values directly to object properties (e.g. `label.textColor`).
- Manage lifetimes with `.store(in:)` on Task sets, just like `AnyCancellable`.

### 👀 Observation Integration
- Seamlessly connect to Swift’s new Observation framework.
- Turn `@Observable` properties into streams with `observed(\.property)`.
- Automatically replay the current value, then emit fresh values whenever the property changes.
- Perfect for keeping UI state in sync with your models.

### 🌍 Cross-Platform
- AsyncCombine doesn’t rely on Combine or other Apple-only frameworks.
- Runs anywhere Swift Concurrency works: iOS, macOS, tvOS, watchOS.
- Fully portable to Linux and even SwiftWasm for server-side and web targets.
- Ideal for writing platform-agnostic domain logic and unit tests.

### 🔁 State Relay
- Ship values through your app with a hot, replay-1 async primitive.
- `CurrentValueRelay<Value>` holds the latest value and broadcasts it to all listeners.
- Similar to Combine’s `CurrentValueSubject`, but actor-isolated and async-first.
- Exposes an AsyncStream for easy consumption in UI or domain code.

### ⚡ Async Algorithms Compatible
- Compose richer pipelines using Swift Async Algorithms.
- Add `.debounce`, `.throttle`, `.merge`, `.zip`, and more to your async streams.
- Chain seamlessly with AsyncCombine operators (`sink`, `assign`, etc.).
- Great for smoothing UI inputs, combining event streams, and building complex state machines.

## 🚀 Usage

### Observe @Observable properties
Turn any `@Observable` property into an `AsyncStream` that replays the current value and then emits on every change. Chain standard `AsyncSequence` operators (`map`, `filter`, `compactMap`, ...) and finish with `sink` or `assign`.

```swift
import AsyncCombine
import Observation

@Observable @MainActor
final class CounterViewModel {
    var count: Int = 0
}

let viewModel = CounterViewModel()
var subscriptions = Set<SubscriptionTask>()

// $viewModel.count  →  viewModel.observed(\.count)
viewModel.observed(\.count)
    .map { "Count: \($0)" }
    .sink { print($0) }
    .store(in: &subscriptions)

viewModel.count += 1  // prints "Count: 1"
```

Why it works: `observed(_:)` uses `withObservationTracking` under the hood and reads on `MainActor`, so you always get the fresh value (no stale reads).

### Bind to UI (UIKit / AppKit / SpriteKit / custom objects)

```swift
// UILabel example
let label = UILabel()

viewModel.observed(\.count)
    .map {
        UIColor(
            hue: CGFloat($0 % 360) / 360,
            saturation: 1,
            brightness: 1,
            alpha: 1
        )
    }
    .assign(to: \.textColor, on: label)
    .store(in: &subscriptions)
```
Works the same for `NSTextField.textColor, `SKShapeNode.fillColor`, your own class properties, etc.

### Use CurrentValueRelay for hot, replay-1 state

`CurrentValueRelay<Value>` holds the latest value and broadcasts it to all listeners. `stream()` yields the current value immediately, then subsequent updates.

```swift
let relay = CurrentValueRelay(false)
var subs = Set<SubscriptionTask>()

relay.stream()
    .map { $0 ? "ON" : "OFF" }
    .sink { print($0) }                // "OFF" immediately (replay)
    .store(in: &subs)

Task {
    await relay.send(true)             // prints "ON"
    await relay.send(false)            // prints "OFF"
}
```

Cancel tasks when you’re done (e.g., deinit).

```swift
subs.cancelAll()
```

### Debounce, throttle, merge (with Swift Async Algorithms)

AsyncCombine plays nicely with [Swift Async Algorithms]. Import it to get reactive operators you know from Combine.

```swift
import AsyncAlgorithms

viewModel.observed(\.count)
    .debounce(for: .milliseconds(250))   // smooth noisy inputs
    .map { "Count: \($0)" }
    .sink { print($0) }
    .store(in: &subscriptions)
```
You can also `merge` multiple streams, `zip` them, `removeDuplicates`, etc.

### Lifecycle patterns (Combine-style ergonomics)

Keep your subscriptions alive as long as you need them:
```swift
final class Monitor {
    private var subscriptions = Set<SubscriptionTask>()
    private let vm: CounterViewModel

    init(vm: CounterViewModel) {
        self.vm = vm

        vm.observed(\.count)
            .map(String.init)
            .sink { print("Count:", $0) }
            .store(in: &subscriptions)
    }

    deinit {
        subscriptions.cancelAll()
    }
}
```

### Handle throwing streams (works for both throwing & non-throwing)

`sink(catching:_:)` uses an iterator under the hood, so you can consume throwing sequences too. If your pipeline introduces errors, add an error handler:

```swift
someThrowingAsyncSequence   // AsyncSequence whose iterator `next()` can throw
    .map { $0 }             // your transforms here
    .sink(catching: { error in
        print("Stream error:", error)
    }) { value in
        print("Value:", value)
    }
    .store(in: &subscriptions)
```
If your stream is non-throwing (e.g., `AsyncStream`, `relay.stream()`), just omit `catching:`.

### Quick Reference

- `observed(\.property)` → `AsyncStream<Value>` (replay-1, Observation-backed)
- `sink { value in … }` → consume elements (returns Task you can cancel or `.store(in:)`)
- `assign(to:on:)` → main-actor property binding
- `CurrentValueRelay<Value>` → `send(_:)`, `stream(replay: true)`
- `subscriptions.cancelAll()` → cancel everything (like clearing AnyCancellables)

### SwiftUI Tip
SwiftUI already observes `@Observable` models. You usually don’t need `observed(_:)` inside a View for simple UI updates—bind directly to the model. Use `observed(_:)` when you need pipelines (`debounce`, `merge`, etc) or when binding to non-SwiftUI objects (eg., SpriteKit, UIKit).

## 📦 Installation

Add this to your Package.swift:
```swift
dependencies: [
    .package(url: "https://github.com/your-username/AsyncCombine.git", from: "1.0.0")
]
```

Or in Xcode: File > Add Packages... and paste the repo URL.

## Author

[William Lumley](https://lumley.io/), will@lumley.io

## License

AsyncCombine is available under the MIT license. See the LICENSE file for more info.
