# AsyncCombine

AsyncCombine brings familiar Combine-style operators — `sink`, `assign`, and `store(in:)` — to the world of Swift Concurrency.
It’s built on top of AsyncSequence and integrated with Swift’s Observation framework, so you can react to @Observable model changes, bind values to UI, and manage state across platforms (iOS, macOS, Linux, SwiftWasm) — all without importing Combine.
It also ships with CurrentValueRelay, a replay-1 async primitive inspired by Combine’s `CurrentValueSubject`, giving you a simple way to bridge stateful streams between domain logic and presentation.

✨ Features

**Combine-like Syntax**
- Use .sink {}, .assign(to:on:), and .store(in:) with AsyncSequence.

**Observation Integration**
- @Observable models → AsyncStream via observed(\.property).

**Cross Platform**
- Works anywhere Swift Concurrency does: iOS, macOS, Linux, SwiftWasm.

**State Relay**
- CurrentValueRelay<Value> for replay-1 hot streams, fully actor-isolated.

**Async Algorithms Compatible**
- Add operators like debounce, throttle, merge, etc. with Swift Async Algorithms.

📦 Installation

**Swift Package Manager**
Add this to your Package.swift:
```swift
dependencies: [
    .package(url: "https://github.com/your-username/AsyncCombine.git", from: "1.0.0")
]
```

Or in Xcode: File > Add Packages... and paste the repo URL.

🚀 Usage

**Observing `@Observable` properties**

```swift
import AsyncCombine
import Observation

@Observable @MainActor
final class CounterViewModel {
    var count: Int = 0
}

let viewModel = CounterViewModel()
var subscriptions = Set<SubscriptionTask>()

viewModel.observed(\.count)
    .map { "Count: \($0)" }
    .sink { print($0) }
    .store(in: &subscriptions)

viewModel.count += 1  // prints "Count: 1"
```

**Binding to UI**

shapeNode // SKShapeNode

```swift
label // UILabel

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

**Using ``CurrentValueRelay`**

```swift
let relay = CurrentValueRelay(false)
var subs = Set<SubscriptionTask>()

relay.stream()
    .map { $0 ? "ON" : "OFF" }
    .sink { print($0) }
    .store(in: &subs)

Task {
    await relay.send(true)   // prints "ON"
    await relay.send(false)  // prints "OFF"
}

```

🛠 API Overview
- AsyncSequence.sink(_:) → consume elements with async closure
- AsyncSequence.assign(to:on:) → assign values to object properties on the main actor
- .store(in:) → cancelable subscriptions (like AnyCancellable)
- Observable.observed(\.property) → turn @Observable key paths into streams
- CurrentValueRelay<Value> → replay-1 async state holder with .send() and .stream()
