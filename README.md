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

AsyncCombine brings familiar Combine-style operators like `sink`, `assign`, and `store(in:)` to the world of Swift Concurrency.

While Swift Concurrency has certainly been an improvement over Combine when combined (heh) with swift-async-algorithms, managing multiple subscriptions can be quite a messy process.

Introducing, AsyncCombine! It’s built on top of `AsyncSequence` and integrated with Swift’s `Observation` framework, so you can react to `@Observable` model changes, bind values to UI, and manage state, all without importing Combine. Beacuse of this, it works on any platform that Swift runs on, from iOS and macOS to Linux and SwiftWasm.

It also ships with CurrentValueRelay, a replay-1 async primitive inspired by Combine’s `CurrentValueSubject`, giving you a simple way to bridge stateful streams between domain logic and presentation.

While async/await brought clarity and safety to Swift’s concurrency story, working directly with AsyncSequence can sometimes feel verbose and clunky, especially when compared to Combine’s elegant, declarative pipelines. With Combine, you chain operators fluently (map → filter → sink) and manage lifetimes in one place. By contrast, async/await often forces you into nested for await loops, manual task management, and boilerplate cancellation. AsyncCombine bridges this gap: it keeps the expressive syntax and ergonomics of Combine while running entirely on Swift Concurrency. You get the readability of Combine pipelines, without the overhead of pulling in Combine itself or losing portability.

Let's get into the nuts and bolts of it all and look into how AsyncCombine can improve your Swift Concurrency exerience.

So say you have a View Model like below.
```swift
@Observable @MainActor
final class CounterViewModel {
    var count: Int = 0
}
```

In a traditional async/await setup, you would listen to the new value being published like so.
```swift
let viewModel = CounterViewModel()

let countChanges = Observations {
    self.viewModel.count
}

Task {
    for await count in countChanges.map({ "Count: \($0)" }) {
        print("\(count)")
    }
}
```

However with AsyncCombine you can express the same logic in a more concise and easy to read format.
```swift
var subscriptions = Set<SubscriptionTask>()

viewModel.observed(\.count)
    .map { "Count: \($0)" }
    .sink { print($0) }
    .store(in: &subscriptions)
```


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

### 🔁 CurrentValueSubject Replacement
- Ship values through your app with a hot, replay-1 async primitive.
- `CurrentValueRelay<Value>` holds the latest value and broadcasts it to all listeners.
- Similar to Combine’s `CurrentValueSubject`, but actor-isolated and async-first.
- Exposes an AsyncStream for easy consumption in UI or domain code.

### 🔗 Publishers.CombineLatest Replacement
- Use Swift Async Algorithms' `combineLatest(_:_:)` to pair AsyncSequences and emit the latest tuple whenever either side produces a new element (after both have emitted at least once).
- Finishes per CombineLatest semantics, and cancellation propagates to both upstreams.
- Chain it straight into AsyncCombine's `sink`, `assign`, and `store(in:)`.

### ⚡ Async Algorithms Compatible
- Compose richer pipelines using Swift Async Algorithms.
- Add `.debounce`, `.throttle`, `.merge`, `.zip`, and more to your async streams.
- Chain seamlessly with AsyncCombine operators (`sink`, `assign`, etc.).
- Great for smoothing UI inputs, combining event streams, and building complex state machines.

### 🌍 Cross-Platform
- AsyncCombine doesn’t rely on Combine or other Apple-only frameworks.
- Runs anywhere Swift Concurrency works: iOS 17+, macOS 14+, tvOS 17+, watchOS 10+.
- The `AsyncSequence` operators (`sink`, `assign`, `store(in:)`) and `CurrentValueRelay` are fully portable to Linux and SwiftWasm; the Observation-backed `observed(_:)` requires Apple platforms.
- Ideal for writing platform-agnostic domain logic and unit tests.

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

await relay.stream()
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

### Combine multiple AsyncSequences into a single AsyncSequence

```swift
import AsyncAlgorithms
import AsyncCombine

// Two arbitrary async streams
let a = AsyncStream<Int> { cont in
    Task {
        for i in 1...3 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            cont.yield(i)   // 1, 2, 3
        }
        cont.finish()
    }
}

let b = AsyncStream<String> { cont in
    Task {
        for s in ["A", "B"] {
            try? await Task.sleep(nanoseconds: 150_000_000)
            cont.yield(s)   // "A", "B"
        }
        cont.finish()
    }
}

// combineLatest-style pairing (from Swift Async Algorithms)
var tasks = Set<SubscriptionTask>()

combineLatest(a, b)
    .map { i, s in "Pair: \(i) & \(s)" }
    .sink { print($0) }
    .store(in: &tasks)

// Prints (timing-dependent, after both have emitted once):
// "Pair: 2 & A"
// "Pair: 3 & A"
// "Pair: 3 & B"

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
- `CurrentValueRelay<Value>` → `await send(_:)`, `await stream()` (replay-1)
- `subscriptions.cancelAll()` → cancel everything (like clearing AnyCancellables)

### SwiftUI Tip
SwiftUI already observes `@Observable` models. You usually don’t need `observed(_:)` inside a View for simple UI updates—bind directly to the model. Use `observed(_:)` when you need pipelines (`debounce`, `merge`, etc) or when binding to non-SwiftUI objects (eg., SpriteKit, UIKit).

## 🧪 Testing

AsyncCombine ships with lightweight testing utilities that make it easy to record, inspect, and assert values emitted by AsyncSequences.
This lets you write deterministic async tests without manual loops, sleeps, or boilerplate cancellation logic.

### 📹 Testing with Recorder

The `Recorder` class helps you capture and assert values emitted by any `AsyncSequence`.

It continuously consumes the sequence on a background task and buffers each element, allowing your test to await them one by one with predictable timing.

```swift
import AsyncCombine
import Testing  // or XCTest

@Test
func testRelayEmitsExpectedValues() async throws {
    let relay = CurrentValueRelay(0)
    let recorder = await relay.stream().record()

    await relay.send(1)
    await relay.send(2)

    let first = try await recorder.next()
    let second = try await recorder.next()

    #expect(first == 1)
    #expect(second == 2)
}
```

`Recorder` makes it easy to verify asynchronous behaviour without juggling timers or nested loops.

If the next value doesn’t arrive within the timeout window, it automatically reports a failure (via `Issue.record` or `XCTFail`, depending on your test framework).

### 🥇 Finding the First Matching Value

`AsyncCombine` also extends `AsyncSequence` with a convenience helper for asserting specific values without fully consuming the sequence.

```swift
import AsyncCombine
import Testing

@Test
func testStreamEmitsSpecificValue() async throws {
    let stream = AsyncStream<Int> { cont in
        cont.yield(1)
        cont.yield(2)
        cont.yield(3)
        cont.finish()
    }

    // Wait for the first element equal to 2.
    let match = await stream.first(equalTo: 2)
    #expect(match == 2)
}
```

This suspends until the first matching element arrives, or returns nil if the sequence finishes first.

It’s ideal when you just need to confirm that a certain value appears somewhere in an async stream.

## 📦 Installation

Add this to your Package.swift:
```swift
dependencies: [
    .package(url: "https://github.com/will-lumley/AsyncCombine.git", from: "2.0.0")
]
```

Or in Xcode: File > Add Packages... and paste the repo URL.

## 📚 Documentation

AsyncCombine ships full DocC documentation. Generate it locally with the [Swift DocC Plugin](https://github.com/apple/swift-docc-plugin):

```bash
swift package --disable-sandbox generate-documentation --target AsyncCombine
```

Or in Xcode: Product > Build Documentation.

## Author

[William Lumley](https://lumley.io/), will@lumley.io

## License

AsyncCombine is available under the MIT license. See the LICENSE file for more info.
