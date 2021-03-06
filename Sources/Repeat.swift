//
//  ProcedureKit
//
//  Copyright © 2016 ProcedureKit. All rights reserved.
//

import Foundation

public struct RepeatProcedurePayload<T: Operation> {
    public typealias ConfigureBlock = (T) -> Void

    public let operation: T
    public let delay: Delay?
    public let configure: ConfigureBlock?

    public init(operation: T, delay: Delay? = nil, configure: ConfigureBlock? = nil) {
        self.operation = operation
        self.delay = delay
        self.configure = configure
    }
}

open class RepeatProcedure<T: Operation>: GroupProcedure {

    public typealias Payload = RepeatProcedurePayload<T>

    static func create<V>(withMax max: Int? = nil, andIterator base: V) -> (T, AnyIterator<Payload>) where V: IteratorProtocol, V.Element == Payload {

        var base = base
        guard let payload = base.next() else { preconditionFailure("Payload Iterator must return an instance initially.") }

        if let max = max {
            return (payload.operation, AnyIterator(FiniteIterator(base, limit: max - 1)))
        }
        return (payload.operation, AnyIterator(base))
    }

    static func create<D, V>(withMax max: Int? = nil, andDelay delay: D, andIterator base: V) -> (T, AnyIterator<Payload>) where D: IteratorProtocol, D.Element == Delay, V: IteratorProtocol, V.Element == T {
        let tmp = MapIterator(PairIterator(primary: base, secondary: delay)) { Payload(operation: $0.0, delay: $0.1) }
        return create(withMax: max, andIterator: tmp)
    }

    public internal(set) var previous: T? = nil

    /// - returns: the currently executing operation instance of T
    public internal(set) var current: T

    /// - returns: the number of operation instances
    public internal(set) var count: Int = 1

    internal private(set) var configure: Payload.ConfigureBlock = { _ in }

    private var iterator: AnyIterator<Payload>

    public init<PayloadIterator>(max: Int? = nil, iterator base: PayloadIterator) where PayloadIterator: IteratorProtocol, PayloadIterator.Element == Payload {
        (current, iterator) = RepeatProcedure.create(withMax: max, andIterator: base)
        super.init(operations: [])
    }

    public init<OperationIterator, DelayIterator>(max: Int? = nil, delay: DelayIterator, iterator base: OperationIterator) where OperationIterator: IteratorProtocol, DelayIterator: IteratorProtocol, OperationIterator.Element == T, DelayIterator.Element == Delay {
        (current, iterator) = RepeatProcedure.create(withMax: max, andDelay: delay, andIterator: base)
        super.init(operations: [])
    }

    public init<OperationIterator>(max: Int? = nil, wait: WaitStrategy = .immediate, iterator base: OperationIterator) where OperationIterator: IteratorProtocol, OperationIterator.Element == T {
        (current, iterator) = RepeatProcedure.create(withMax: max, andDelay: Delay.iterator(wait.iterator), andIterator: base)
        super.init(operations: [])
    }

    public init(max: Int? = nil, wait: WaitStrategy = .immediate, body: @escaping () -> T?) {
        (current, iterator) = RepeatProcedure.create(withMax: max, andDelay: Delay.iterator(wait.iterator), andIterator: AnyIterator(body))
        super.init(operations: [])
    }

    /// Public override of execute which configures and adds the first operation
    open override func execute() {
        configure(current)
        add(child: current)
        super.execute()
    }

    open override func childWillFinishWithoutErrors(_ child: Operation) {
        addNextOperation(child === current)
    }

    open override func child(_ child: Operation, willAttemptRecoveryFromErrors errors: [Error]) -> Bool {
        addNextOperation(child === current)
        return super.child(child, willAttemptRecoveryFromErrors: errors)
    }

    /// Adds the next payload from the iterator to the queue.
    ///
    /// - parameter shouldAddNext: must evaluate true to get the next payload. Defaults to true.
    ///
    /// - returns: whether or not there was a next payload added.
    @discardableResult
    public func addNextOperation(_ shouldAddNext: @autoclosure () -> Bool = true) -> Bool {
        guard !isCancelled && shouldAddNext(), let payload = next() else { return false }

        log.notice(message: "Will add next operation.")

        if let newConfigureBlock = payload.configure {
            replace(configureBlock: newConfigureBlock)
        }

        configure(payload.operation)

        if let delay = payload.delay.map({ DelayProcedure(delay: $0) }) {
            payload.operation.add(dependency: delay)
            add(children: delay, payload.operation)
        }
        else {
            add(child: payload.operation)
        }

        count += 1
        previous = current
        current = payload.operation

        return true
    }

    /// Returns the next operation from the generator. This is here to
    /// allow subclasses to override and configure the operation
    /// further before it is added.
    ///
    /// - returns: an optional Paylod
    public func next() -> Payload? {
        return iterator.next()
    }

    /// Appends a configuration block to the current block. This
    /// can be used to configure every instance of the operation
    /// before it is added to the queue.
    ///
    /// Note that configuration block are executed in FIFO order,
    /// so it is possible to overwrite previous configurations.
    ///
    /// - parameter block: a block which receives an instance of T
    public func append(configureBlock block: @escaping Payload.ConfigureBlock) {
        let config = configure
        configure = { operation in
            config(operation)
            block(operation)
        }
    }

    public func appendConfigureBlock(block: @escaping Payload.ConfigureBlock) {
        append(configureBlock: block)
    }

    /// Replaces the current configuration block
    ///
    /// If the payload returns a configure block, it replaces using
    /// this API, before configuring
    ///
    /// - parameter block: a block which receives an instance of T
    public func replace(configureBlock block: @escaping Payload.ConfigureBlock) {
        configure = block
        log.verbose(message: "did replace configure block.")
    }

    public func replaceConfigureBlock(block: @escaping Payload.ConfigureBlock) {
        replace(configureBlock: block)
    }
}




// MARK: - Iterators

public struct CountingIterator<Element>: IteratorProtocol {

    private let body: (Int) -> Element?
    public private(set) var count: Int = 0

    public init(_ body: @escaping (Int) -> Element?) {
        self.body = body
    }

    public mutating func next() -> Element? {
        defer { count = count + 1 }
        return body(count)
    }
}

public func arc4random<T: ExpressibleByIntegerLiteral>(_ type: T.Type) -> T {
    var r: T = 0
    arc4random_buf(&r, Int(MemoryLayout<T>.size))
    return r
}

public struct RandomFailIterator<Element>: IteratorProtocol {

    private var iterator: AnyIterator<Element>
    private let shouldNotFail: () -> Bool

    public let probability: Double

    public init<I: IteratorProtocol>(_ iterator: I, probability prob: Double = 0.1) where I.Element == Element {
        self.iterator = AnyIterator(iterator)
        self.shouldNotFail = {
            let r = (Double(arc4random(UInt64.self)) / Double(UInt64.max))
            return r > prob
        }
        self.probability = prob
    }

    public mutating func next() -> Element? {
        guard shouldNotFail() else { return nil }
        return iterator.next()
    }
}

public struct FibonacciIterator: IteratorProtocol {
    var currentValue = 0, nextValue = 1

    public mutating func next() -> Int? {
        let result = currentValue
        currentValue = nextValue
        nextValue += result
        return result
    }
}

public struct FiniteIterator<Element>: IteratorProtocol {

    private var iterator: CountingIterator<Element>

    public init<I: IteratorProtocol>(_ iterator: I, limit: Int = 10) where I.Element == Element {
        var mutable = iterator
        self.iterator = CountingIterator { count in
            guard count < limit else { return nil }
            return mutable.next()
        }
    }

    public mutating func next() -> Element? {
        return iterator.next()
    }
}

public struct MapIterator<Element, T>: IteratorProtocol {

    private let transform: (Element) -> T
    private var iterator: AnyIterator<Element>

    public init<I: IteratorProtocol>(_ iterator: I, transform: @escaping (Element) -> T) where I.Element == Element {
        self.iterator = AnyIterator(iterator)
        self.transform = transform
    }

    public mutating func next() -> T? {
        return iterator.next().map(transform)
    }
}

public struct PairIterator<T, V>: IteratorProtocol {

    private var primary: AnyIterator<T>
    private var secondary: AnyIterator<V>

    public init<Primary: IteratorProtocol, Secondary: IteratorProtocol>(primary: Primary, secondary: Secondary) where Primary.Element == T, Secondary.Element == V {
        self.primary = AnyIterator(primary)
        self.secondary = AnyIterator(secondary)
    }

    public mutating func next() -> (T, V?)? {
        return primary.next().map { ($0, secondary.next()) }
    }
}

// MARK: - IntervalIterator

public struct IntervalIterator {

    public static let immediate = AnyIterator { TimeInterval(0) }

    public static func constant(_ constant: TimeInterval = 1.0) -> AnyIterator<TimeInterval> {
        return AnyIterator { constant }
    }

    public static func random(withMinimum min: TimeInterval = 0.0, andMaximum max: TimeInterval = 10.0) -> AnyIterator<TimeInterval> {
        return AnyIterator {
            let r = (Double(arc4random(UInt64.self)) / Double(UInt64.max))
            return (r * (max - min)) + min
        }
    }

    public static func incrementing(from initial: TimeInterval = 0.0, by increment: TimeInterval = 1.0) -> AnyIterator<TimeInterval> {
        return AnyIterator(CountingIterator { count in
            let interval = initial + (increment * TimeInterval(count))
            return max(0, interval)
        })
    }

    public static func fibonacci(withPeriod period: TimeInterval = 1.0, andMaximum maximum: TimeInterval = TimeInterval(Int.max)) -> AnyIterator<TimeInterval> {
        return AnyIterator(MapIterator(FibonacciIterator()) { fib in
            let interval = period * TimeInterval(fib)
            return max(0, min(maximum, interval))
        })
    }

    public static func exponential(power: Double = 2.0, withPeriod period: TimeInterval = 1.0, andMaximum maximum: TimeInterval = TimeInterval(Int.max)) -> AnyIterator<TimeInterval> {
        return AnyIterator(CountingIterator { count in
            let interval = period * pow(power, Double(count))
            return max(0, min(maximum, interval))
        })
    }
}

public extension Delay {

    public static func iterator(_ iterator: AnyIterator<TimeInterval>) -> AnyIterator<Delay> {
        return AnyIterator(MapIterator(iterator) { Delay.by($0) })
    }

    public struct Iterator {

        static func iterator(_ iterator: AnyIterator<TimeInterval>) -> AnyIterator<Delay> {
            return Delay.iterator(iterator)
        }

        public static let immediate: AnyIterator<Delay> = iterator(IntervalIterator.immediate)

        public static func constant(_ constant: TimeInterval = 1.0) -> AnyIterator<Delay> {
            return iterator(IntervalIterator.constant(constant))
        }

        public static func random(withMinimum min: TimeInterval = 0.0, andMaximum max: TimeInterval = 10.0) -> AnyIterator<Delay> {
            return iterator(IntervalIterator.random(withMinimum: min, andMaximum: max))
        }

        public static func incrementing(from initial: TimeInterval = 0.0, by increment: TimeInterval = 1.0) -> AnyIterator<Delay> {
            return iterator(IntervalIterator.incrementing(from: initial, by: increment))
        }

        public static func fibonacci(withPeriod period: TimeInterval = 1.0, andMaximum maximum: TimeInterval = TimeInterval(Int.max)) -> AnyIterator<Delay> {
            return iterator(IntervalIterator.fibonacci(withPeriod: period, andMaximum: maximum))
        }

        public static func exponential(power: Double = 2.0, withPeriod period: TimeInterval = 1.0, andMaximum maximum: TimeInterval = TimeInterval(Int.max)) -> AnyIterator<Delay> {
            return iterator(IntervalIterator.exponential(power: power, withPeriod: period, andMaximum: maximum))
        }
    }
}

public enum WaitStrategy {
    case immediate
    case constant(TimeInterval)
    case random(minimum: TimeInterval, maximum: TimeInterval)
    case incrementing(initial: TimeInterval, increment: TimeInterval)
    case fibonacci(period: TimeInterval, maximum: TimeInterval)
    case exponential(power: Double, period: TimeInterval, maximum: TimeInterval)

    public var iterator: AnyIterator<TimeInterval> {
        switch self {
        case .immediate:
            return IntervalIterator.immediate
        case let .constant(constant):
            return IntervalIterator.constant(constant)
        case let .random(minimum: min, maximum: max):
            return IntervalIterator.random(withMinimum: min, andMaximum: max)
        case let .incrementing(initial: initial, increment: increment):
            return IntervalIterator.incrementing(from: initial, by: increment)
        case let .fibonacci(period: period, maximum: max):
            return IntervalIterator.fibonacci(withPeriod: period, andMaximum: max)
        case let .exponential(power: power, period: period, maximum: max):
            return IntervalIterator.exponential(power: power, withPeriod: period, andMaximum: max)
        }
    }
}
