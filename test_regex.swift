import Foundation
let text = "<think>testing\nnewlines</think>Hello"
let result = text.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
print(result)
let text2 = "<think>S</think>Hello"
let result2 = text2.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
print(result2)
