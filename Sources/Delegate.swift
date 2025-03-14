import Foundation

public actor Delegate<Input, Output> where Input: Sendable, Output: Sendable {
    public init() {}

    private var block: ((Input) -> Output?)?
    private var asyncBlock: ((Input) async -> Output?)?
    
    public func delegate<T: AnyObject>(on target: T, block: ((T, Input) -> Output)?) {
        self.block = { [weak target] input in
            guard let target = target else { return nil }
            return block?(target, input)
        }
    }
    
    public func delegate<T: AnyObject>(on target: T, block: ((T, Input) async -> Output)?) {
        self.asyncBlock = { [weak target] input in
            guard let target = target else { return nil }
            return await block?(target, input)
        }
    }

    public func call(_ input: Input) -> Output? {
        return block?(input)
    }

    public func callAsFunction(_ input: Input) -> Output? {
        return call(input)
    }
    
    public func callAsync(_ input: Input) async -> Output? {
        return await asyncBlock?(input)
    }
    
    public var isSet: Bool {
        block != nil || asyncBlock != nil
    }
}

extension Delegate where Input == Void {
    public func call() -> Output? {
        return call(())
    }

    public func callAsFunction() -> Output? {
        return call()
    }
}

extension Delegate where Input == Void, Output: OptionalProtocol {
    public func call() -> Output {
        return call(())
    }

    public func callAsFunction() -> Output {
        return call()
    }
}

extension Delegate where Output: OptionalProtocol {
    public func call(_ input: Input) -> Output {
        if let result = block?(input) {
            return result
        } else {
            return Output._createNil
        }
    }

    public func callAsFunction(_ input: Input) -> Output {
        return call(input)
    }
}

public protocol OptionalProtocol {
    static var _createNil: Self { get }
}
extension Optional : OptionalProtocol {
    public static var _createNil: Optional<Wrapped> {
         return nil
    }
}
