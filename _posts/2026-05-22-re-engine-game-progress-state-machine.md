---
layout: post
title: Figuring out the RE Engine (Resident Evil Requiem's game engine) game progress state machine.
subtitle: Discovering the RE Engine behavior tree.
gh-repo: IamSanjid/zig_reframework_plugin
gh-badge: [watch, follow]
tags: [c/c++, zig, reverse-engineering, x86_64, assembly]
author: IamSanjid
---

## Final Result
We discover how the RE Engine (Resident Evil Requiem's version) handles the game progress state machine and how we can forcefully trigger our desired game progress state.

{: .box-warning}
**Disclaimer:** I do not condone any form of cheating that would degrade other people's experience. This repository/blog doesn't directly show anything that would benefit a user's in-game online activities.



## The Game
It's [Resident Evil Requiem](https://store.steampowered.com/app/3764200/Resident_Evil_Requiem/), which was released in February 2026. This is the latest installment of the Resident Evil series and is built on the RE Engine, Capcom's proprietary game engine.

The game uses a state machine for tracking its in-game progress. While these types of state machines are usually seen for handling animation states, the game uses it for the entire game's progress. From an area being loaded to a cutscene being played, everything is handled by this state machine, executed after every state transition.

So, if you forcefully use a mod to gain an item required for a puzzle to unlock the next area, the game might not even load that area, causing your character to go out-of-bounds and fall through the map. The state machine is responsible for loading the next area; there are states represented as "Behavior Trees," which are essentially trees of nodes containing Selector Args, Condition Args, Action Args, etc. These stored parameters are used to determine whether to execute the current Behavior Tree and queue the next one.

### Notes on the RE Engine
RE Engine utilizes IL2CPP, which is essentially a C# to C++ converter. They primarily write the game in C# and then convert it to C++ using their IL2CPP "compiler." However, the semantics remain the same as the C# version; some extra arguments are passed to functions to maintain the VM context and stack context to match the C# runtime. The engine stores type information in memory for C# reflection and parent-child class relationship detection.

Engine native functions (C++ functions) can call C# functions directly and vice versa. Usually, managed functions (C# functions) are called by passing a VM Context as the first parameter, which stores stack information, exceptions, return results, etc. I am not sure if that's exactly how the newer .NET AOT compilation works, but the engine demonstrates a clean way to interop between C# and C++.

#### Setting goals...
Okay, so the goal is to find out how this state-machine works in-memory and how we can forcefully trigger our desired game progress state. 

### Tools
* **Cheat Engine**: For debugging, memory scanning, and finding function addresses.
* **[REFramework](https://github.com/praydog/REFramework)**: An existing RE Engine modding framework that provides many useful APIs for modding the game. It is primarily used to disable anti-debugging protections.
* **IDA**: For static analysis and decompiling assembly into somewhat readable C code.

## Ready, set, go
So, how do we get started? First, we need to dump the runtime "unpacked" game's .exe. Since the game uses Denuvo, we can't perform static analysis on the normal .exe; we have to dump it. Use any reliable method to dump the runtime version and load that into IDA.

Remember, our goal is to forcefully trigger our game progress state. One thing we want to do is load the next in-game chapter, which is related to a "Scene-Transition." Using REFramework's **Developer Tools -> Object Explorer -> Singletons**, we can find a class named `app.SceneTransitionManager`.

![app.SceneTransitionManager First](https://i.ibb.co.com/Z1fGq1tW/image.png)

It's a singleton, meaning it likely handles all scene loading. It has a function named `requestMainGameJumpCore`.

![requestMainGameJumpCore First](https://i.ibb.co.com/8LnS6qLp/image.png)

REFramework has a feature that can hook a function and identify its caller. If we're lucky, a C# (converted) function might be calling it, rather than a native engine function. We can right-click and hook it. We could also set a breakpoint using any debugger to trace the stack return pointer, but REFramework provides nicely detected function names, which simplifies things.

After hooking, we can trigger the loading of a new in-game chapter by playing manually.

A member function of `app.LevelFlowManager` calls it, and from the REFramework Object Explorer, we can see it is also a singleton.

![requestGameJump First](https://i.ibb.co.com/Kj6WVTmL/image.png)

If we hook this function again and resume gameplay, we see something like `*BehaviorTreeAction*.start(via.behaviortree.ActionArg)`.

![GameJumpAction.start First](https://i.ibb.co.com/HvKZ3BB/image.png)

All of this should sound familiar if you've been reading from the start, but let's pretend we don't know anything about it yet.
If we hook this function again, you will see that no function name is shown because an RE Engine native function is calling this managed function.

#### Some more insights...

Every C# class inherits from `ManagedObject`, which roughly looks like this:
```c++
struct ManagedObject {
    void** type_info;
    int32_t ref_count;
    int32_t padding1;
    // Maybe something more...
};
```

How did I know? Thanks to REFramework's contributors and author. If you think about it, it makes sense to store it this way; there is still a runtime Garbage Collector to match the semantics and behavior of a normal C# application.

`void** type_info` also acts as a VTable. At offset 0, it contains the actual `TypeDefinition*` (the type metadata), and after some metadata, it points to virtual functions. We will discover more about this later.

#### Continuing...

**Note:** The offsets, addresses, and struct layouts mentioned below may differ depending on the game version. They are shown here for analysis purposes.

Now we're kind of stuck since we don't know much about `*BehaviorTreeAction*.start(via.behaviortree.ActionArg)`, who is calling it, or what logic is being applied...<br>
Time to bring out our trusty debugger, Cheat Engine. Make sure VEH debugging is enabled and set a breakpoint on this function. We can get the address by right-clicking and selecting "Copy Address" from the REFramework context menu.

It was `0x1480673a0` for me. Upon hitting the breakpoint, let's look at the function calling convention and arguments to understand what's going on.

RCX = VM context  
RDX = `this` pointer (*ManagedObject* instance)  
R8 = argument 1  
R9 = argument 2  
Stack...

The convention is similar to the typical C++ x64 Windows calling convention, where RCX is the VM context pointer, RDX is the `this` pointer, and the remaining arguments are passed in R8/R9, with any others pushed onto the stack.

This is what the stack return address looks like:

![stack_return_address 1](https://i.ibb.co.com/LzjzPt6r/image.png)

Okay, let's speed up a little. If we set a breakpoint at `re9.exe+1042D2EB`, it doesn't get hit until something happens, meaning it's likely not in a loop or an update function called every frame.

If we go back through the stack return addresses one by one and set a breakpoint at each, we find that `re9.exe+4D16127` is hit every frame, acting as a loop or update function.

```asm
re9.exe+4D16118 - 48 8B 03              - mov rax,[rbx]
re9.exe+4D1611B - 48 89 D9              - mov rcx,rbx
re9.exe+4D1611E - 48 89 FA              - mov rdx,rdi
re9.exe+4D16121 - FF 90 88000000        - call qword ptr [rax+00000088]
```

Here it's moving `rbx` to `rcx`, `rax` is the VTable pointer, and `[rax+00000088]` is the virtual function pointer for the "update" method.

Since we're passing the `this` pointer through the `rcx` register, it's not a managed function, as the VM context is supposed to be passed through `rcx` for those.

RE Engine managed objects can also have native member functions, which are called primarily from engine systems like the game loop or physics engine. Since managed functions don't call these, they aren't included in the type metadata mentioned earlier.

One clean way to check if this `rcx` pointer is a managed object or a native object is via REFramework's Object Explorer.

![REFramework ObjectExplorer](https://i.ibb.co.com/WpqhWd6K/image.png)

We can paste the `rcx` value here to see if it's a managed or native object.

![managed object 1](https://i.ibb.co.com/Fb7S0Js1/image.png)

And luckily, it's a managed object of type `via.behaviortree.BehaviorTree`. In most cases, the `via` namespace contains almost fully native objects; it feels like a wrapper around native objects for managed code to use. Consequently, the type metadata doesn't contain all field and method information.

Note: REFramework's current BehaviorTree implementation is outdated; using it will crash the game.
Opening the function `re9.exe+4D16121` in IDA, shows something like this:

![IDA 1](https://i.ibb.co.com/15cRC5v/image.png)

I defined `BehaviorTree` in IDA like this and performed some custom analysis to understand the function's objective:
```c
struct __declspec(align(8)) BehaviorTree
{
  uint8_t _obj_padding[16];
  // These are part of via.Component, which BehaviorTree inherits. Found these from REFramework type info.
  void *owner;
  void *child_component;
  void *next_component;
  void *prev_component;
  // Actual fields to be discussed later...
  CoreHandleArray handle_array;
  uint32_t queue_group;
  int32_t index_in_queue;
  uint8_t _padding2[100];
  uint8_t can_execute;
  uint8_t padding3[16];
  BehaviorTree *next;
  BehaviorTree *prev;
  uint32_t queue_index;
  uint8_t unknown[512];
};
```

Notice this?
```c
(*(void (__fastcall **)(BehaviorTree *, __int64 *))(*(_QWORD *)k->_obj_padding + 0x88i64))(k, &v10);
```

`v10` is the VM context here. They pass a pointer to it or perhaps return it/the stack state.

The function appears to be popping a `BehaviorTree` from a queue and executing its actions. The code follows a standard lock-free queue pop implementation, using atomic `compare and exchange` operations for safety.

So, how do we proceed? It's likely reading the head of the queue from `a1 + 0x440`, popping it, and setting the next Behavior Tree as the new head.

If we look at the assembly, we see `mov rcx, [rbx+0x000000C0]` at `re9.exe+4D160C7`. `rbx` is the "this" pointer for the Behavior Tree. We can see that at offset `0xC0`, it is getting the next Behavior Tree to set as the new head. This instruction was near a `lock cmpxchg [rsi+0x00000440], rcx` operation. From this, we can infer the `BehaviorTree` struct layout, at least for the next/prev pointers. The `prev` pointer is typically near the `next` pointer (usually +/- 8 bytes); manual verification confirmed it at +8 bytes.

Now, we check what writes to `a1 + 0x440`. We can set a hardware write breakpoint on that address in Cheat Engine. Since `a1` is a singleton instance, its address remains constant throughout the session.

Two results appeared: one popping the head and another setting it with a new value:
```asm
re9.exe+55C71CA - 4B 8B 84 FD E0000000  - mov rax,[r13+r15*8+000000E0]
re9.exe+55C71D2 - 48 89 86 40040000     - mov [rsi+00000440],rax
```

And the function in IDA looks like:

![IDA 2](https://i.ibb.co.com/4nyPcpG2/image.png)

Let's focus on this:
```c
v10 = *(_QWORD *)(a1 + 0x450) + 0x510 * i;
// ...
v12 = -8i64;
// ...
v13 = *(_QWORD *)(v10 + 8 * v12 + 0xE0);
*(_QWORD *)(a1 + 0x440) = v13;
```

While other things are happening in this function, this is where the Behavior Tree head is being set. We don't need to worry about everything; just focus on these bits. Let's see what's at `a1 + 0x450` and what the `v13` value is when `i` is 0.

For me, `*(a1 + 0x450)` is `0x137622630`. Ignoring the incrementing `v12`, the first `v13` value is `*(0x137622630 + (8*-8) + 0xE0)`, which is `0x118AAFD7C0`. Using REFramework's Object Inspector:

![ObjectExplorer 2](https://i.ibb.co.com/CsD8n58J/image.png)

It is indeed a `BehaviorTree`. Let's fast forward and see what writes to `0x137622630 + (8*-8) + 0xE0`—the `v13` value that eventually becomes the head of the Behavior Tree.

When reloading or loading a save, I found that:
```asm
re9.exe+56DE84 - 4B 89 14 C2           - mov [r10+r8*8],rdx
```
This is where the code writes to `0x137622630 + (8*-8) + 0xE0` (the `v13` value).

Here is the decompiled function in IDA:

![IDA 3](https://i.ibb.co.com/nMwcZ8xq/image.png)

I named the following fields:
- `mov eax, [rdx+0D0h]` (offset `0xD0`): `queue_index`
- `movsxd r14, dword ptr [rdx+40h]` (offset `0x40`): `queue_group`
- `movsxd r8, dword ptr [rdi+44h]` (offset `0x44`): `index_in_queue`

Here, `rdi` and `rdx` registers contain the address of the `BehaviorTree` node being removed, and `a1` is the BehaviorTree handler singleton mentioned earlier, which pops the head and executes the next update.

#### Guessing time...

From this function and the previous one (`re9.exe+55C71CA`), we can infer that there are multiple Behavior Tree queues, likely preset by the developers—one for animations, one for UI, one for game progress, etc.

The logic suggests there are 8 types of Behavior Tree queues, each with a different `queue_group` value. Why 8? Remember the `v12` value was set to `-8` in the previous function. This is likely part of the engine's hardcoded Behavior Tree queue management.

As I write this, I suspect `mov eax, [rdx+0D0h]` (offset `0xD0`) should actually be named `queue_group` and `movsxd r14, dword ptr [rdx+40h]` (offset `0x40`) something else.

Actually, the function calculates `v8 = 0x1B0 * [rdx+0x40]` and uses it as follows:
`p_prev = (BehaviorTree **)(v8 + v4 + 0xE0 + 8 * index_in_queue);`
This might be an index indicating the "root" Behavior Tree node in the queue. It executes when the `prev` Behavior Tree is null, meaning the current one is the first in the queue.

#### What we have so far

When I say "Behavior Tree node," I'm referring to a `BehaviorTreeQueue` containing a `BehaviorTree* node`. Each item in the queue is a node.

* We've inferred there are 8 types of Behavior Tree queues, each with a different `queue_group` value (likely 0–7).
* Each Behavior Tree is assigned an index, ID, or handle, likely for fast access.
* A thread might switch the queue head to alternate between different queues, possibly determined by a thread-local value.
* The function `re9.exe+4D16121` calls the execute/update function of the next Behavior Tree in the current queue.
* This eventually calls the actions defined in the nodes, such as our target `GameJumpAction`.
* The struct layout for `BehaviorTree` is:
  - **0x00**: Type information
  - **0x08**: Reference count
  - **0x0C**: Padding
  - **0x10**: Start of actual Behavior Tree data
  - **0x40**: Root Behavior Tree node index/handle
  - **0x44**: Current Behavior Tree node index/handle
  - **0xC0**: Next Behavior Tree node in the queue
  - **0xC8**: Previous Behavior Tree node in the queue
  - **0xD0**: Queue group index/handle?

#### Reversing the BehaviorTree layout more...

Let's go back to the stack return addresses for `*BehaviorTree*GameJumpAction.start`:

![stack_return_address 1](https://i.ibb.co.com/LzjzPt6r/image.png)

Which function was called after `re9.exe+4D16121 - FF 90 88000000 - call qword ptr [rax+00000088]`? (The Behavior Tree's 'update'/'execute' function called each frame).

IDA decompilation of `re9.exe+53AD888`:

![IDA 3](https://i.ibb.co.com/SXjBZjmR/image.png)

This is how the `CoreHandleArray` struct is defined in IDA:
```c
struct CoreHandleArray
{
  CoreHandle **handles;
  int len;
};
```

In function `re9.exe+53AD888`, we see `mov r14, [rcx+30h]`, where `rcx` points to a `BehaviorTree`. At offset `0x30` is the start of the `CoreHandleArray`. Notably, it's stored directly as a value within the `BehaviorTree` struct, not as a pointer.

And `CoreHandle` is defined as:
```c
struct CoreHandle
{
  uint8_t _obj_padding[16];
  void *_padding1;
  Core core;
  uint8_t unknown[40];
};
```

`CoreHandle` is a `ManagedObject`, but its type info lacks details on the `Core` struct, meaning `Core` is not a `ManagedObject` itself. (Note: These names are somewhat arbitrary, though `CoreHandle` matches the type info `via.behaviortree.BehaviorTree.CoreHandle`).

Why do I believe `Core` is a separate struct stored directly in `CoreHandle` as a value? Because of calls like `sub_1453AD8F0(&current_handle->core, a2);` and:

```asm
re9.exe+53AD881 - 48 8D 4B 18           - lea rcx,[rbx+18]
re9.exe+53AD885 - 48 89 F2              - mov rdx,rsi
re9.exe+53AD888 - E8 63000000           - call re9.exe+53AD8F0
```

`rbx` is the `CoreHandle` pointer; `[rbx+18]` is the `Core` struct within it. `lea rcx, [rbx+18]` gets the address (equivalent to `&current_handle->core`) and passes it to `call re9.exe+53AD8F0`.

That function eventually calls `*BehaviorTree*GameJumpAction.start`, triggering the scene transition.

By reversing these further, we can determine the layout of `Core` and how the action argument is stored.

The final layout of `Core` at least the parts we care about:
```c
struct __declspec(align(8)) Core
{
  void **vtable;
  TreeObject *tree_object;
  uint8_t pad1[32];
  void *selector_arg;
  ActionArg *action_arg;
  void *condition_arg;
  void *selector_condition_arg;
  void *selector_caller_arg;
  void *transition_event_arg;
  void *user_variables_hub;
  void *maybe_next_component;
  uint8_t pad2[64];
  void *owner_component;
  uint8_t unknown[512];
};
```

If we check further into these functions and the stack return addresses for `*BehaviorTree*GameJumpAction.start`:

![stack_return_address 1](https://i.ibb.co.com/LzjzPt6r/image.png)

We can eventually figure out the following structures (note that these names are arbitrary, though based on their function):

```c
struct __declspec(align(8)) TreeObjectData
{
  uint8_t pad1[176];
  uint32_t some_count;
  uint8_t unknown[512];
};

struct NodeArray
{
  void *nodes;
  uint32_t len;
};

struct ManagedArray
{
  void **items;
  uint32_t len;
  uint32_t capacity;
};

struct TreeObject
{
  void *vfptr;
  uint8_t pad1[24];
  TreeObjectData *data;
  NodeArray nodes;
  uint8_t pad2[16];
  ManagedArray actions;
  uint8_t pad3[96];
  ManagedArray selectors;
  uint8_t unknown[768];
};
```

Btw these struct names are completely arbitrary, just made those up whatever made sense to me at the time.

Notice that `TreeObject` has a field called `actions`, which contains a collection of `ManagedObjects` similar to our target `*BehaviorTree*GameJumpAction`.

One more thing about `re9.exe+4D16121 - FF 90 88000000 - call qword ptr [rax+00000088]` (the 'update'/'execute' function of the Behavior Tree):

```asm
re9.exe+4D16118 - 48 8B 03              - mov rax,[rbx]
re9.exe+4D1611B - 48 89 D9              - mov rcx,rbx
re9.exe+4D1611E - 48 89 FA              - mov rdx,rdi
re9.exe+4D16121 - FF 90 88000000        - call qword ptr [rax+00000088]
```

`rbx` is the `BehaviorTree` instance pointer.

`mov rax, [rbx]` moves the "type information." At offset `0x00` is the `TypeDefinition` pointer—metadata about the `BehaviorTree` type. There are other fields as well, but at offset `0x88`, there is a function pointer to the "update"/"execute" function. The takeaway is that this type information contains flattened function pointers alongside the type definition and other metadata.

#### Conclusion

In summary, we have determined how the `BehaviorTree` type information is structured, how the game invokes the "update"/"execute" function, and how a game frame update processes the Behavior Tree queue to execute actions sequentially.

However, we haven't triggered it ourselves yet. If we examine the `app.LevelFlowManager` singleton and its `_ManagedObjectList` field:

![LevelFlowManager _ManagedObjectList](https://i.ibb.co.com/SXNgPbT7/image.png)

Each `app.LevelFlowManagedObject` instance is a `via.Component` instance, and each has a child component of type `via.behaviortree.BehaviorTree`. This is our target!

How did I discover this? I used REFramework's plugin capabilities to hook the `*BehaviorTree*GameJumpAction.ctor` function (the constructor). Since it's a virtual constructor, I had to verify if the current `this` pointer type matched the `*BehaviorTree*GameJumpAction` type.

After logging the instance address, I searched for it in memory using Cheat Engine and reverse-searched for the `ManagedArray` containing it. Since `ManagedArray` is in a `TreeObject`, I then searched for the `Core` instance containing that `TreeObject`. Finding `Core`'s address allowed me to subtract `0x18` to get the `CoreHandle` address. From there, I reverse-searched for the `CoreHandle` address to find the `CoreHandleArray`, then the `BehaviorTree`, then the owner `GameObject`, and finally, other children of that `GameObject`.

Ultimately, we can retrieve all `BehaviorTree` instances of the current "level" from `app.LevelFlowManagedObject._ManagedObjectList`, get the child component with the `BehaviorTree` type, and call the `+0x88` offset function pointer to start any instance. Since multiple threads execute different Behavior Trees, we should start ours in one of those threads to avoid race conditions.

For a concrete implementation of this, check out this [Zig example from my zig_reframework_plugin project](https://github.com/IamSanjid/zig_reframework_plugin/blob/main/src/examples/re9_forced/behavior_tree.zig).
