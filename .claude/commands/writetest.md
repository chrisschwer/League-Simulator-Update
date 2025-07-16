Write comprehensive tests for $ARGUMENTS following these guidelines:

1. **Test Coverage Strategy**:
   - Aim for >90% code coverage
   - Cover all public APIs and interfaces
   - Test both happy paths and error scenarios
   - Include edge cases identified in analysis

2. **Unit Tests**:
   - Test individual functions/methods in isolation
   - Mock external dependencies
   - Verify return values and side effects
   - Test boundary conditions

3. **Integration Tests**:
   - Test component interactions
   - Verify data flow between modules
   - Test with real dependencies where appropriate
   - Ensure proper error propagation

4. **Test Organization**:
   - Group related tests logically
   - Use descriptive test names that explain what and why
   - Follow AAA pattern: Arrange, Act, Assert
   - Include setup and teardown as needed

5. **Error Scenarios**:
   - Invalid inputs
   - Network failures
   - Timeout conditions
   - Concurrent access issues
   - Resource exhaustion

6. **Performance Tests** (where applicable):
   - Response time requirements
   - Throughput testing
   - Memory usage validation
   - Scalability verification

Follow the project's existing test patterns and frameworks. Make tests readable, maintainable, and reliable.