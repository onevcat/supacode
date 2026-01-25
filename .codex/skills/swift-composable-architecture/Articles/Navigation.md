# Navigation

Learn how to use the navigation tools in the library, including how to best model your domains, how
to integrate features in the reducer and view layers, and how to write tests.

## Overview

State-driven navigation is a powerful concept in application development, but can be tricky to
master. The Composable Architecture provides the tools necessary to model your domains as concisely
as possible and drive navigation from state, but there are a few concepts to learn in order to best
use these tools.

## Topics

### Essentials

- [What is navigation?](WhatIsNavigation.md)

### Tree-based navigation

- [Tree-based navigation](TreeBasedNavigation.md)
- `Presents()`
- `PresentationAction`
- `Reducer.ifLet(_:action:destination:fileID:filePath:line:column:)-4ub6q`

### Stack-based navigation

- [Stack-based navigation](StackBasedNavigation.md)
- `StackState`
- `StackAction`
- `StackActionOf`
- `StackElementID`
- `Reducer.forEach(_:action:destination:fileID:filePath:line:column:)-9svqb`

### Dismissal

- `DismissEffect`
- `Dependencies.DependencyValues.dismiss`
- `Dependencies.DependencyValues.isPresented`
