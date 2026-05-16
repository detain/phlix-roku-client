# Phlex Roku Developer Guide

This document provides detailed information for developers working on the Phlex Roku application.

## Architecture Overview

### Application Flow

```
┌─────────────────────────────────────────────────────────────┐
│                        PhlexApp                             │
│  (Main application controller - entry point)               │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  LoginScene     │  │   HomeScene     │  │  LibraryScene    │
│  (Authentication)│  │  (Main browse)  │  │  (Media browse)  │
└─────────────────┘  └─────────────────┘  └─────────────────┘
                                                     │
                                                     ▼
                                           ┌─────────────────┐
                                           │  DetailScene    │
                                           │ (Item details)  │
                                           └─────────────────┘
                                                     │
                                                     ▼
                                           ┌─────────────────┐
                                           │  PlayerScene    │
                                           │ (Video player)  │
                                           └─────────────────┘
```

### Data Flow

1. **User Input** → Remote button press
2. **Scene Component** → Handles key event
3. **Manager Classes** → Business logic
4. **ApiClient** → HTTP API calls
5. **Response** → Parse JSON, update UI

### Key Components

| Component | Responsibility |
|-----------|----------------|
| `PhlexApp` | Main app controller, scene navigation |
| `ApiClient` | All HTTP communication with Phlex server |
| `AuthManager` | Authentication state and token management |
| `SessionManager` | Session lifecycle management |
| `LibraryManager` | Library browsing and item retrieval |
| `Storage` | Persistent local storage (registry) |
| `TaskManager` | Background task scheduling |

## Component Structure

### Scene Components (XML + BrightScript)

Each scene consists of two files:
- `*.xml` - Scene graph layout definition
- `*.brs` - Component logic and event handlers

#### XML Structure

```xml
<?xml version="1.0" encoding="utf-8"?>
<component name="ComponentName" extends="Scene">
    <script type="text/brightscript" uri="ComponentName.brs"/>

    <!-- Interface for script-accessible fields -->
    <interface>
        <field id="data" type="string" />  <!-- observable -->
    </interface>

    <!-- Child nodes -->
    <children>
        <Rectangle id="background" />
        <Label id="title" text="Hello" />
    </children>
</component>
```

#### BrightScript Structure

```brightscript
sub Init()
    ' Called when component is created
    m.top.SetFocus(true)
end sub

sub OnDataChange()
    ' Observer for m.top.data field
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    ' Handle remote button events
    return true  ' if handled
end sub
```

### Library Components

The `source/lib/` directory contains pure BrightScript modules:

- **ApiClient** - Factory function returning API object
- **Storage** - Factory function returning storage object
- **Managers** - Factory functions returning manager objects

## BrightScript Coding Standards

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Functions | PascalCase | `GetUserData()` |
| Variables | camelCase | `userName`, `isLoggedIn` |
| Constants | UPPER_SNAKE | `MAX_RETRIES`, `API_TIMEOUT` |
| Component IDs | camelCase | `titleLabel`, `playButton` |
| Fields | camelCase | `m.top.userData` |
| Files | PascalCase + .brs | `ApiClient.brs`, `LibraryManager.brs` |

### Function Guidelines

```brightscript
' Good: Descriptive name, typed parameters, typed return
function GetUserById(id as String) as Object
    return m.request("GET", "/Users/" + id, {})
end function

' Good: Void function for side effects
sub LogMessage(message as String)
    print "[INFO] " + message
end sub

' Avoid: Generic names, untyped parameters
function get(id)
    ' ... code ...
end function
```

### Variable Declaration

```brightscript
' Local variables - always use specific types
localVariable = "string"  ' implicit string
count as Integer = 0      ' explicit integer

' Component fields - use m.top for interface
m.top.fieldName = value

' Module-level variables - at top of function
function ApiClient(baseUrl as String) as Object
    obj = {
        baseUrl: baseUrl        ' public field
        privateField: ""        ' private by convention
    }
    return obj
end function
```

### Control Flow

```brightscript
' If statements - always use then on same line or endif
if condition then
    ' code
end if

' Short form for simple returns
if token = "" then return invalid

' Select Case
select case action
    case "play"
        DoPlay()
    case "pause"
        DoPause()
    case else
        DoNothing()
end select

' Loops
for each item in itemList
    process(item)
end for

for i = 0 to 10
    if i = 5 then exit for
end for
```

### Error Handling

```brightscript
' Check for invalid before using
if user <> invalid then
    process(user)
end if

' Use Try/Catch for graceful degradation
sub SafeOperation()
    try
        riskyOperation()
    catch e
        print "Error: " + e.message
    end try
end sub

' Return error indicators
function getData() as Object
    data = m.request("GET", "/data", {})
    if data = invalid then
        print "Failed to fetch data"
        return {}
    end if
    return data
end function
```

## Scene Graph Best Practices

### Memory Management

1. **Reuse nodes** when possible instead of creating new
2. **Remove unused children** when navigating away
3. **Avoid deep nesting** of components
4. **Use `SetFocus()`** only on visible, interactive nodes

### Performance Guidelines

```brightscript
' Good: Create only visible items
sub ShowGrid(items as Object)
    m.grid.RemoveChildren(m.grid.GetChildren())
    for each item in items
        ' create and add one at a time
    end for
end sub

' Avoid: Creating all items upfront if not visible
```

### Focus Management

```brightscript
' Set focus on the correct initial node
sub Init()
    m.top.SetFocus(true)
end sub

' Handle focus changes
sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false
    if press then
        if key = "OK" then
            m.button.ObserveField("buttonSelected", "OnButtonPress")
            handled = true
        end if
    end if
    return handled
end sub
```

### Observers

```brightscript
' Observe field changes
m.top.ObserveField("data", "OnDataChange")

' Define observer function
sub OnDataChange()
    ' Access changed value via m.top.data
    if m.top.data <> invalid then
        updateUI(m.top.data)
    end if
end sub

' Stop observing when done
m.top.UnObserveField("data")
```

### Animation

```brightscript
' Use BrightScript animation API
rect = m.top.FindNode("animatedRect")

animation = CreateObject("roSGNode", "Vector2DFieldInterpolator")
animation.fieldToInterp = rect.translation
animation.key = [0.0, 1.0]
animation.keyValue = [[0, 0], [500, 0]]
animation.duration = 1.0

node = CreateObject("roSGNode", "Animation")
node.addChild(animation)
node.control = "start"
m.top.addChild(node)
```

## Testing Guide

### Test File Structure

```brightscript
' tests/unit/ApiClient.test.brs

' Test helper functions (provided by test framework)
sub assertEqual(actual, expected)
    if actual <> expected then
        print "FAIL: " + actual + " <> " + expected
    end if
end sub

sub assertTrue(value as Boolean)
    if not value then
        print "FAIL: expected true"
    end if
end sub

' Individual test functions
sub TestApiClientInit()
    client = ApiClient("http://localhost:8096")
    assertEqual(client.deviceType, "roku")
    print "TestApiClientInit passed"
end sub

sub TestApiClientToken()
    client = ApiClient("http://localhost:8096")
    client.setToken("test-token")
    assertEqual(client.token, "test-token")
    print "TestApiClientToken passed"
end sub
```

### Writing Tests

1. **Arrange** - Set up test data
2. **Act** - Call the function under test
3. **Assert** - Verify expected results

```brightscript
sub TestStorageSetAndGet()
    ' Arrange
    storage = Storage()

    ' Act
    storage.set("test_key", "test_value")
    value = storage.get("test_key")

    ' Assert
    assertEqual(value, "test_value")

    ' Cleanup
    storage.delete("test_key")
end sub
```

### Test Categories

| Category | Location | Purpose |
|----------|----------|---------|
| Unit | `tests/unit/*.test.brs` | Test individual functions |
| Integration | `tests/integration/*.test.brs` | Test API integration |

### Running Tests

```bash
# List tests
make test

# Deploy to device for actual execution
make install
```

### Mocking

Since BrightScript doesn't have a mocking framework:

```brightscript
' Create mock storage for testing
function MockStorage() as Object
    storage = {}
    storage.data = {}
    storage.set = function(key as String, value as String)
        m.data[key] = value
    end function
    storage.get = function(key as String) as String
        if m.data.DoesExist(key) then
            return m.data[key]
        end if
        return ""
    end function
    return storage
end function
```

## API Integration

### Request Format

```brightscript
' All API calls go through ApiClient.request()
response = m.api.request("GET", "/Items/" + id, {})

' POST with body
response = m.api.request("POST", "/Playstate", {
    session_id: m.sessionId
    command: "play"
})
```

### Response Handling

```brightscript
if response <> invalid then
    ' Success - response is parsed JSON object
    process(response)
else
    ' Failure - handle error
    showError()
end if
```

### Error Codes

| Code | Meaning | Handling |
|------|---------|----------|
| 401 | Unauthorized | Re-authenticate |
| 403 | Forbidden | Check permissions |
| 404 | Not Found | Show "not available" |
| 500 | Server Error | Retry with backoff |
| timeout | Network timeout | Show retry option |

## Debugging

### Print Debugging

```brightscript
print "DEBUG: variable = " + str(variable)
print "DEBUG: object = "; object  ' semi-colon for objects
```

### Telnet Debugging

```bash
# Connect to Roku device
telnet ROKU_IP 8080

# Common commands
help        ' Show available commands
list        ' List all components
vars        ' Show global variables
bt          ' Stack backtrace
continue    ' Resume execution
quit        ' Disconnect
```

### Variable Inspection

```bash
# In telnet session
? m.global.sessionId
? m.top.data
watch m.top.data  ' Watch for changes
```

## Common Patterns

### Navigation Pattern

```brightscript
' In PhlexApp.brs
sub ShowHome()
    homeScene = CreateObject("roSGNode", "HomeScene")
    m.top.Append(homeScene)
    homeScene.SetFocus(true)
end sub

sub NavigateToScene(sceneName as String)
    scene = CreateObject("roSGNode", sceneName)
    m.top.Append(scene)
    scene.SetFocus(true)
end sub
```

### Loading State Pattern

```brightscript
sub LoadData()
    m.top.findNode("spinner").visible = true

    ' Async load
    m.api.getLibraries()

    m.top.findNode("spinner").visible = false
end sub
```

### Error State Pattern

```brightscript
sub OnApiError(error as Object)
    if error.code = 401 then
        ' Force re-login
        m.top.RemoveChild(m.top.GetChild(m.top.GetChildCount() - 1))
        ShowLogin()
    else
        ' Show error message
        m.top.findNode("errorLabel").text = error.message
    end if
end sub
```

## Code Review Checklist

Before merging any BrightScript code:

- [ ] All functions have typed parameters and return values
- [ ] No `print` statements left in production code (except debug)
- [ ] Error handling for all API calls
- [ ] Memory cleanup (remove observers, unused children)
- [ ] Focus properly managed
- [ ] Tests added/updated for new functionality
- [ ] No hardcoded URLs or credentials
- [ ] Comments explain "why", not "what"
