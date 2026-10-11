import Foundation

/// 属性计算器 - 实现属性计算的逻辑
class AttributeCalculator {
    private let databaseManager: DatabaseManager

    private lazy var step1 = Step1(databaseManager: databaseManager)
    private lazy var step2 = Step2(databaseManager: databaseManager)
    private lazy var step3 = Step3(databaseManager: databaseManager)
    private lazy var step4 = Step4(databaseManager: databaseManager, step3: step3)
    private lazy var step5 = Step5(databaseManager: databaseManager)

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    /// 计算属性并生成输出 - 使用新的输出模型
    /// - Parameter input: 模拟输入数据
    /// - Returns: 包含计算结果的模拟输出数据
    func calculateAndGenerateOutput(input: SimulationInput) -> SimulationOutput {
        // 创建输入的副本
        var preparedInput = input

        // 执行Step1 - 类型和效果采集阶段
        Logger.info("执行Step1 - 类型和效果采集阶段")
        let itemEffects = step1.process(input: input)

        // 效果模板不依赖当前属性值，直接解析采集到的效果。
        let attributeModifiers = step2.process(itemEffects: itemEffects)
        Logger.info("Step2完成 - 解析了\(attributeModifiers.count)个修饰器")

        // 执行Step3 - 将修饰器应用到物品属性上
        Logger.info("执行Step3 - 将修饰器应用到物品属性上")
        preparedInput = step3.process(
            input: preparedInput,
            attributeModifiers: attributeModifiers
        )
        Logger.info("Step3完成 - 成功应用修饰器到物品属性上")

        // 执行Step4 - 递归计算属性最终值
        Logger.info("执行Step4 - 递归计算属性最终值")
        var output = step4.process(input: preparedInput)
        Logger.info("Step4完成 - 成功计算所有属性的最终值")

        // 执行Step5 - 推进模块速度修正
        Logger.info("执行Step5 - 推进模块速度修正")
        output = step5.process(output: output)
        Logger.info("Step5完成 - 推进模块速度修正完成")

        return output
    }
}
