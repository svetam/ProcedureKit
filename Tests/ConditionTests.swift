//
//  ProcedureKit
//
//  Copyright © 2016 ProcedureKit. All rights reserved.
//

import XCTest
import TestingProcedureKit
@testable import ProcedureKit

class ConditionTests: ProcedureKitTestCase {

    // MARK: - Condition Unit Tests

    func test__true_condition_is_satisfied() {
        let condition = TrueCondition()
        condition.evaluate(procedure: procedure) { result in
            guard case .satisfied = result else {
                XCTFail("TrueCondition did not evaluate as satisfied."); return
            }
        }
    }

    func test__false_condition_is_failed() {
        let condition = FalseCondition()
        condition.evaluate(procedure: procedure) { result in
            guard case let .failed(error) = result else {
                XCTFail("FalseCondition did not evaluate as failed."); return
            }
            XCTAssertTrue(error is ProcedureKitError.FalseCondition)
        }
    }

    func test__condition_which_is_executed_without_a_procedure() {
        let condition = TrueCondition()
        wait(for: condition)
        XCTAssertProcedureFinishedWithoutErrors(condition)
    }

    // MARK: - Single Attachment

    func test__single_condition_which_is_satisfied() {
        procedure.attach(condition: TrueCondition())
        wait(for: procedure)
        XCTAssertProcedureFinishedWithoutErrors()
    }

    func test__single_condition_which_is_failed() {
        procedure.attach(condition: FalseCondition())
        wait(for: procedure)
        XCTAssertProcedureCancelledWithErrors()
    }

    // MARK: - Multiple Attachment

    func test__multiple_conditions_where_all_are_satisfied() {
        procedure.attach(condition: TrueCondition())
        procedure.attach(condition: TrueCondition())
        procedure.attach(condition: TrueCondition())
        wait(for: procedure)
        XCTAssertProcedureFinishedWithoutErrors()
    }

    func test__multiple_conditions_where_all_fail() {
        procedure.attach(condition: FalseCondition())
        procedure.attach(condition: FalseCondition())
        procedure.attach(condition: FalseCondition())
        wait(for: procedure)
        XCTAssertProcedureCancelledWithErrors(count: 3)
    }

    func test__multiple_conditions_where_one_succeeds() {
        procedure.attach(condition: TrueCondition())
        procedure.attach(condition: FalseCondition())
        procedure.attach(condition: FalseCondition())
        wait(for: procedure)
        XCTAssertProcedureCancelledWithErrors(count: 2)
    }

    func test__multiple_conditions_where_one_fails() {
        procedure.attach(condition: TrueCondition())
        procedure.attach(condition: TrueCondition())
        procedure.attach(condition: FalseCondition())
        wait(for: procedure)
        XCTAssertProcedureCancelledWithErrors(count: 1)
    }

    // MARK: - Nested Conditions

    func test__single_condition_with_single_condition_which_both_succeed__executes() {
        let condition = TrueCondition()
        condition.attach(condition: TrueCondition())
        procedure.attach(condition: condition)
        wait(for: procedure)
        XCTAssertProcedureFinishedWithoutErrors()
    }

    func test__single_condition_which_succeeds_with_single_condition_which_fails__cancelled() {
        let condition = TrueCondition(name: "Condition 1")
        condition.attach(condition: FalseCondition(name: "Nested Condition 1"))
        procedure.attach(condition: condition)
        wait(for: procedure)
        XCTAssertProcedureCancelledWithErrors(count: 1)
    }

    // MARK: - Conditions with Dependencies

    func test__dependencies_execute_before_condition_dependencies() {

        let dependency1 = TestProcedure(name: "Dependency 1")
        let dependency2 = TestProcedure(name: "Dependency 2")
        procedure.add(dependencies: dependency1, dependency2)

        let conditionDependency1 = BlockOperation {
            XCTAssertTrue(dependency1.isFinished)
            XCTAssertTrue(dependency2.isFinished)
        }
        conditionDependency1.name = "Condition 1 Dependency"

        let condition1 = TrueCondition(name: "Condition 1")
        condition1.add(dependency: conditionDependency1)


        let conditionDependency2 = BlockOperation {
            XCTAssertTrue(dependency1.isFinished)
            XCTAssertTrue(dependency2.isFinished)
        }
        conditionDependency2.name = "Condition 2 Dependency"

        let condition2 = TrueCondition(name: "Condition 2")
        condition2.add(dependency: conditionDependency2)

        procedure.attach(condition: condition1)
        procedure.attach(condition: condition2)

        run(operations: dependency1, dependency2)
        wait(for: procedure)

        XCTAssertProcedureFinishedWithoutErrors(dependency1)
        XCTAssertProcedureFinishedWithoutErrors(dependency2)
        XCTAssertProcedureFinishedWithoutErrors()
    }

    func test__dependencies_contains_direct_dependencies_and_indirect_dependencies() {

        let dependency1 = TestProcedure()
        let dependency2 = TestProcedure()
        let condition1 = TrueCondition(name: "Condition 1")
        condition1.add(dependency: TestProcedure())
        let condition2 = TrueCondition(name: "Condition 2")
        condition2.add(dependency: TestProcedure())

        procedure.add(dependency: dependency1)
        procedure.add(dependency: dependency2)
        procedure.attach(condition: condition1)
        procedure.attach(condition: condition2)

        run(operations: dependency1, dependency2)
        wait(for: procedure)

        XCTAssertEqual(procedure.dependencies.count, 4)
    }

    func test__target_and_condition_have_same_dependency() {
        let dependency = TestProcedure()
        let condition = TrueCondition(name: "Condition")
        condition.add(dependency: dependency)

        procedure.attach(condition: condition)
        procedure.add(dependency: dependency)

        wait(for: dependency, procedure)

        XCTAssertProcedureFinishedWithoutErrors(dependency)
        XCTAssertProcedureFinishedWithoutErrors()
    }

    func test__procedure_is_direct_dependency_and_indirect_of_different_procedures() {
        // See OPR-386
        let dependency = TestProcedure(name: "Dependency")

        let condition1 = TrueCondition(name: "Condition 1")
        condition1.add(dependency: dependency)

        let procedure1 = TestProcedure(name: "Procedure 1")
        procedure1.attach(condition: condition1)
        procedure1.add(dependency: dependency)

        let condition2 = TrueCondition(name: "Condition 2")
        condition2.add(dependency: dependency)

        let procedure2 = TestProcedure(name: "Procedure 2")
        procedure2.attach(condition: condition2)
        procedure2.add(dependency: procedure1)

        wait(for: procedure1, dependency, procedure2)

        XCTAssertProcedureFinishedWithoutErrors(dependency)
        XCTAssertProcedureFinishedWithoutErrors(procedure1)
        XCTAssertProcedureFinishedWithoutErrors(procedure2)
    }

    // MARK: - Ignored Conditions

    func test__ignored_failing_condition_does_not_result_in_failure() {
        let procedure1 = TestProcedure(name: "Procedure 1")
        procedure1.attach(condition: IgnoredCondition(FalseCondition()))

        let procedure2 = TestProcedure(name: "Procedure 2")
        procedure2.attach(condition: FalseCondition())

        wait(for: procedure1, procedure2)

        XCTAssertProcedureCancelledWithoutErrors(procedure1)
        XCTAssertProcedureCancelledWithErrors(procedure2, count: 1)
    }

    func test__ignored_satisfied_condition_does_not_result_in_failure() {
        let procedure1 = TestProcedure(name: "Procedure 1")
        procedure1.attach(condition: IgnoredCondition(TrueCondition()))

        let procedure2 = TestProcedure(name: "Procedure 2")
        procedure2.attach(condition: TrueCondition())

        wait(for: procedure1, procedure2)

        XCTAssertProcedureFinishedWithoutErrors(procedure1)
        XCTAssertProcedureFinishedWithoutErrors(procedure2)

    }

    func test__ignored_ignored_condition_does_not_result_in_failure() {
        procedure.attach(condition: IgnoredCondition(IgnoredCondition(FalseCondition())))
        wait(for: procedure)
        XCTAssertProcedureCancelledWithoutErrors()
    }
}

