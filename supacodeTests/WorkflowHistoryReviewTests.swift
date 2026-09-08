import Foundation
import ProwlCLIShared
import Testing

@testable import supacode

struct WorkflowHistoryReviewTests {
  private func start(_ body: String, roles: [String: WorkflowRoleBinding] = [:]) throws -> WorkflowRunMachine {
    let definition = try #require(WorkflowDocumentParser.parse(body).definition)
    return try WorkflowRunMachine.start(
      .init(
        definition: definition, runID: UUID(),
        context: .init(
          scope: .user, definitionPath: nil,
          worktree: .init(id: "wt", name: "test", branch: "main", path: "/tmp/history-review-tests")), bindings: roles),
      now: { Date(timeIntervalSince1970: 100) }
    ).machine
  }

  @Test func controlErrorsKeepCompletedWorkAndErrorAfterCancellation() throws {
    var machine = try start(
      """
      schema: prowl.workflow/v1
      id: error
      name: Error
      steps:
        - id: good
          set: {}
        - id: broken
          if: context.roles.missing.observed.exists
          then: [{id: unreachable, notify: Never}]
      """)
    #expect(machine.run.status.attention?.stepID == "broken")
    _ = machine.apply(.user(.cancel))
    let encoded = try WorkflowRunRecord.makeEncoder().encode(WorkflowRunRecord(run: machine.run))
    let record = try WorkflowRunRecord.makeDecoder().decode(WorkflowRunRecord.self, from: encoded)
    #expect(record.steps.first { $0.id == "good" }?.state == .completed)
    #expect(record.steps.first { $0.id == "broken" }?.error?.contains("missing") == true)
  }

  @Test func controlLimitRetainsExecutedRounds() throws {
    let machine = try start(
      """
      schema: prowl.workflow/v1
      id: limit
      name: Limit
      steps:
        - id: rounds
          while: 'true'
          max_iterations: 2
          steps: [{id: tick, set: {}}]
      """)
    let steps = WorkflowRunRecord(run: machine.run).steps
    #expect(machine.run.status == .iterationLimitReached)
    #expect(steps.filter { $0.id == "tick" && $0.state == .completed }.count == 2)
  }

  @Test func breakUsesItsPositionBeforePoppingTheLoop() throws {
    let machine = try start(
      """
      schema: prowl.workflow/v1
      id: nested
      name: Nested
      state: {count: {type: integer, initial: 0}}
      steps:
        - id: outer
          while: state.count < 2
          steps:
            - id: inner
              while: 'true'
              steps:
                - id: work
                  notify: Work
                - id: stop
                  break: true
            - id: increment
              set: {count: state.count + 1}
      """)
    let steps = WorkflowRunRecord(run: machine.run).steps
    #expect(
      steps.filter { $0.id == "stop" }.map(\.iterationPath) == [["outer:1", "inner:1"], ["outer:2", "inner:1"]])
    #expect(steps.filter { $0.id == "inner" }.map(\.iterationPath) == [["outer:1"], ["outer:2"]])
  }

  @Test func provisionalAndCorrectedSubmissionsKeepBothBodies() throws {
    let pane = WorkflowPaneIdentity(surfaceID: UUID(), tabID: nil, handle: "p1", displayName: "Pi", agent: "pi")
    var machine = try start(
      """
      schema: prowl.workflow/v1
      id: delivery
      name: Delivery
      roles: {author: {source: current}}
      steps:
        - id: review
          message: author
          instruction: Review
          expect: {delivery: report, sections: ['## Findings']}
      """, roles: ["author": .current(pane)])
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "dispatch"))
    let disk = WorkflowRunStore(rootURL: machine.run.context.worktree.rootURL, directory: machine.run.runDirectory)
    try disk.ensureLayout(runID: machine.run.id)
    defer { try? FileManager.default.removeItem(at: machine.run.runDirectory) }
    func persist(_ effects: [WorkflowRunEffect]) throws {
      for case .persistDelivery(let name, let ordinal, let body) in effects {
        try disk.writeDelivery(runID: machine.run.id, name: name, ordinal: ordinal, body: body)
      }
    }
    let first = machine.deliver(ordinal: 1, selector: .manual(stepID: "review"), body: "First output", verdict: nil)
    try persist(first.effects)
    _ = machine.apply(.deliveryPersisted(ordinal: 1))
    #expect(WorkflowRunRecord(run: machine.run).steps.last?.delivery != nil)
    _ = machine.apply(.user(.askAgain))
    let second = machine.deliver(
      ordinal: 1, selector: .manual(stepID: "review"), body: "## Findings\nCorrected output", verdict: nil)
    try persist(second.effects)
    _ = machine.apply(.deliveryPersisted(ordinal: 1))
    let record = WorkflowRunRecord(run: machine.run)
    let json = try #require(
      JSONSerialization.jsonObject(with: WorkflowRunRecord.makeEncoder().encode(record)) as? [String: Any])
    let steps = try #require(json["steps"] as? [[String: Any]])
    let submissions = try #require(steps.last?["submissions"] as? [[String: Any]])
    #expect(submissions.count == 2)
    let paths = try submissions.map { entry -> String in
      let delivery = try #require(entry["delivery"] as? [String: Any])
      return try #require(delivery["path"] as? String)
    }
    #expect(Set(paths).count == 2)
    #expect(try String(contentsOfFile: paths[0], encoding: .utf8).contains("First output"))
    #expect(try String(contentsOfFile: paths[1], encoding: .utf8).contains("Corrected output"))

    var legacy = json
    legacy.removeValue(forKey: "step_definitions")
    legacy["steps"] = steps.map { $0.filter { ["id", "iteration", "state", "ordinal"].contains($0.key) } }
    let decoded = try WorkflowRunRecord.makeDecoder().decode(
      WorkflowRunRecord.self,
      from: JSONSerialization.data(withJSONObject: legacy))
    #expect(WorkflowHistoryStepGroup.groups(decoded).flatMap(\.attempts).compactMap(\.delivery).count == 1)
  }

  @Test func textPreviewKeepsMultibyteBoundariesAndRejectsInvalidData() {
    for scalar in ["é", "中", "🐈"] {
      for offset in 1..<scalar.utf8.count {
        let prefix = String(repeating: "a", count: 4096 - offset)
        let data = Data((prefix + scalar + "tail").utf8)
        #expect(WorkflowHistoryOutputPreview.text(data) == prefix)
      }
    }
    #expect(WorkflowHistoryOutputPreview.text(Data("hello".utf8)) == "hello")
    #expect(WorkflowHistoryOutputPreview.text(Data([0xFF, 0x61])) == nil)
    #expect(WorkflowHistoryOutputPreview.text(Data(repeating: 0x61, count: 4095) + Data([0xFF, 0x61])) == nil)
  }

  @Test func groupingKeepsTenThousandRoundsInNumericOrder() throws {
    let machine = try start(
      """
      schema: prowl.workflow/v1
      id: large
      name: Large
      steps: [{id: tick, set: {}}]
      """)
    let original = WorkflowRunRecord(run: machine.run)
    var object = try #require(
      JSONSerialization.jsonObject(with: WorkflowRunRecord.makeEncoder().encode(original)) as? [String: Any])
    object["steps"] = (1...10_000).map { index in
      ["id": "tick", "state": "completed", "iteration": index, "iterationPath": ["rounds:\(index)"]] as [String: Any]
    }
    let record = try WorkflowRunRecord.makeDecoder().decode(
      WorkflowRunRecord.self,
      from: JSONSerialization.data(withJSONObject: object))
    let groups = WorkflowHistoryStepGroup.groups(record)
    #expect(groups.count == 10_000)
    #expect(groups.map(\.iteration) == Array(1...10_000))
  }

  @Test func longKeysCannotEscapeThePreviewBudget() {
    let key = String(repeating: "k", count: 1_000_000)
    #expect(WorkflowHistoryOutputPreview.json(["output": .object([key: .string("value")])]).utf8.count <= 4096)
  }
}
