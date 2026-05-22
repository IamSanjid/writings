---
layout: post
title: Figuring out RE Engine(Resident Evil Requiem's game engine) game progress state machine.
subtitle: Discovering RE Engine behavior tree.
gh-repo: IamSanjid/zig_reframework_plugin
gh-badge: [watch, follow]
tags: [c/c++, zig, reverse-engineering, x86_64, assembly]
author: IamSanjid
---

## Final Result
We discover how the RE Engine, Resident Evil Requiem's version, handles game progress state machine. And how we can forcefully trigger our desired game progress state.

{: .box-warning}
**Disclaimer:** I do not condone any form of cheating where it would degrade other people's experience. This repository/blog doesn't directly show anything which would benefit an user in-game online activities.



## The Game
It's [Resident Evil Requiem](https://store.steampowered.com/app/3764200/Resident_Evil_Requiem/), which was released in February 2026, the latest installment of the Resident Evil series, and it's built on the RE Engine, which is Capcom's proprietary game engine.

The game uses some sort of State Machine for tracking it's in-game progress, but this type of State Machines is usually seen for handling Animation States, but the game uses it for the whole game's progress. So, from an area being loaded to a cutscene being played, everything is handled by this State Machine, executed after every state transition.

So, if you forcefully use some mod to gain an item, which is a part of some puzzle to unlock the next area, the game wouldn't even load that area, and your character would go out-of-bounds and make you fall through the map. The state-machine is responsible to load the next area, there are states represented as "Behavior Tree", which are basically a tree of nodes, and it contains Selector Arg, Condition Arg, Action Arg etc. these stored parameters are used to determine wheather to execute current "Behavior Tree" and queue the next Behavior Tree.

### Somethings about the RE Engine
RE Engine has il2cpp, which is basically a C# to C++ converter. They mainly write the game in C# and then convert it to C++ using their il2cpp "compiler". But the semantics are still same as the C# version, just some extra arguments are passed to functions to maintain the VM context, stack context to match the C# runtime. The engine stores the type information in memory, for C# reflection, and parent-child class relationship detection.

The engine's native function(C++ functions) can call the C# functions directly and vise-versa, usually the managed functions(C# functions) are called by passing a VM Context as the first paremeter, where it basically stores stack information, exceptions, return result etc.. I am not sure if that's how the newer .Net AoT compilation work, but the engine shows a nice way to interop between C# and C++.

#### Setting goals...
Okay, so the goal is to find out how this state-machine works in-memory and how we can forcefully trigger our desired game progress state. 

### Tools
* Cheat Engine: For debugging, memory scanning, and finding the function's address.
* [REFramework](https://github.com/praydog/REFramework): Existing RE Engine modding framework, which provides a lot of useful APIs for modding the game. It's mainly used to disable the Anti-Debugging protections.
* IDA: For static analysis, and decompiling assembly into somewhat readable C code.

## Ready, set, go
So, how do we get started? We first need to dump the runtime "unpacked" game's .exe, since the game uses denuvo we can't just start static analysis on the normal .exe, so we have to dump it, use any method to dump the runtime version, and give that to IDA.

Okay, remember we want to forcefully trigger our game progress state, so one of the thing is we want to load the next in-game chapter, so something related to "Scene-Transition", using the REFramework's Developers Tool -> Object Explorer -> Singletons, we can see some class named, `app.SceneTransitionManager`

![app.SceneTransitionManager First](https://i.ibb.co.com/Z1fGq1tW/image.png)

It's a singleton, meaning it's probably the one which handles loading scenes always, it has a function named, `requestMainGameJumpCore`

![requestMainGameJumpCore First](https://i.ibb.co.com/8LnS6qLp/image.png)

REFramework has a nice feature it can hook a function and figure out who called the function if we're lucky some C#(converted) function might be calling it, not some native engine function, we can right click and hook it, we could set a breakpoint using any type of debugger, it trace the stack return pointer but REFramework comes with nice detected function names so it's that...

After hooking, we can just trigger in-game new chapter loading by manually playing...

A member function of `app.LevelFlowManager` calls it, and from the REFramework's Object Explorer we can see it's a Singleton..

![requestGameJump First](https://i.ibb.co.com/Kj6WVTmL/image.png)

If we hook this function again and re-play the game, we see, something with `*BehaviorTreeAction*.start(via.behaviortree.ActionArg)`

![GameJumpAction.start First](https://i.ibb.co.com/HvKZ3BB/image.png)

All of these should sound familiar if you've read from the start, but let's pretend we don't know anything about these...<br>
If we hook this function again you will see no function name will be shown, it's because the RE Engine's native function is calling this managed function.

#### Some more insights...

Every C# class inherits `ManagedObject`, which roughly looks like this:
```c++
struct ManagedObject {
    void** type_info;
    int32_t ref_count;
    int32_t padding1;
    // Maybe something more....
};
```

How'd I know? Thanks to REFramework's contributors and author, and if you think about it, it kinda makes sense to store it this way, there is still some runtime Garbage Collecter to match the same semantics and behavior of a normal C# application.

`void** type_info` also kind of acts as a VTable, it just at offset 0 it contains the actual `TypeDefinition*`(the type metadata), and after some metadata information it points to a virtual function, later we will find more about it.

#### Continuing...

Note: The offsets/addresses, struct layouts mentioned below might not be same for all versions of the game. Just shown for analysis purposes.

Now we're kind of stuck since we don't know much about the `*BehaviorTreeAction*.start(via.behaviortree.ActionArg)`, who is calling what logic it's applying to call it...<br>
Time to bring out our trusty debugger, Cheat Engine, make suer VEH debugging is enabled, and set a breakpoint on this function, we can get the address of it by right clicking and selecting "Copy Address" from the REFramework context menu.

It was `0x1480673a0` for me, upon hitting the breakpoint, let's talk about the function calling convention and arguments to understand what's going on.

RCX = vm context
RDX = this pointer, `*BehaviorTreeAction*` instance
R8 = argument1,
R9 = argument2,
Stack...

The convention is similar to typical x64 windows calling convention, where RCX is just the VM context pointer, RDX is the `this` pointer, and rest of the arguments are passed in R8/R9, and the rest are pushed onto the stack.

This is what the stack return address looks like:

![stack_return_address 1](https://i.ibb.co.com/LzjzPt6r/image.png)

Okay, let's speed up a little, if we set a breakpoint at `re9.exe+1042D2E6`, it doesn't get hit until something happens, like it's probably not in a loop, or update function which gets called every game frame.

If we go back to the stack return addresses one by one and set a breakpoint at each one, we can find that at `re9.exe+4D16121` gets hit for every frame, almost like a loop or an update function.

```asm
re9.exe+4D16118 - 48 8B 03              - mov rax,[rbx]
re9.exe+4D1611B - 48 89 D9              - mov rcx,rbx
re9.exe+4D1611E - 48 89 FA              - mov rdx,rdi
re9.exe+4D16121 - FF 90 88000000        - call qword ptr [rax+00000088]
```

So we're moving rbx to rcx, and rax is the Vtable pointer, and `[rax+00000088]` is the virtual function pointer for the "update" method?

Since we're passing `this` pointer through the rcx register, it's not a managed function, since VM context is supposed to be passed through the rcx register for managed functions.

RE Engine managed objects can also have native member functions, and that is mainly called from native functions of the engine, like the game loop or physics engine, and since no managed functions should be calling these, they are also no included in the Type metadata we mentioned earlier.

One nice way to check if this `rcx` pointer is a managed object or a native object is we can check through REFramework's ObjectExplorer.

![REFramework ObjectExplorer](https://i.ibb.co.com/WpqhWd6K/image.png)

We can paste the `rcx` value here to see if it's a managed or native object.

![managed object 1](https://i.ibb.co.com/Fb7S0Js1/image.png)

And luckily, it's a managed object! type name: `via.behaviortree.BehaviorTree`. Oh.. `via.behaviortree` most of the cases `via` namespace are almost fully native objects, to me it feels like just some sort of wrapper around the native object for normal managed objects to use them. And the type metdata doesn't contain all the fields and methods information..

Note: REFramework's current behaviortree implementation is outdated if we try to use its implementation it will crash the game.

Opening the function `re9.exe+4D16121` in IDA, shows something like this:

![IDA 1](https://i.ibb.co.com/15cRC5v/image.png)

I defined `BehaviorTree` in IDA as this and did some custom analysis to understand what the function is trying to do:
```c
struct __declspec(align(8)) BehaviorTree
{
  uint8_t _obj_padding[16];
  // These are part of via.Component, BehaviorTree inherits via.Component. Found these from REFramework Type information.
  void *owner;
  void *child_component;
  void *next_component;
  void *prev_component;
  // The actual fields we will get to it later...
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

Also notice this?
```c
(*(void (__fastcall **)(BehaviorTree *, __int64 *))(*(_QWORD *)k->_obj_padding + 0x88i64))(k, &v10);
```

`v10` is the VM context here. They pass a pointer to the VM context after all, or maybe they return a VM context or the function stack state.

Okay so the function is sort of popping a `BehaviorTree` from the queue and executing its actions? The code is following the book's lock-free queue pop implementation. Compare and exchange atomic operations are used to safely pop the queue.

So, what do we do now? It's probably reading the head(current behavior tree) of the queue from `a1 + 0x440` and then popping the head and setting the next behavior tree as the new head.

So let's pretend we don't know about what BehaviorTree's internal looks like, so naturally if we look at the assembly, we can see this instruction `re9.exe+4D160C7 - 48 8B 8B C0000000     - mov rcx,[rbx+000000C0]
`, `rbx` is the "this behavior tree" pointer. We can clearly see that from "this behavior tree" pointer at offset 0xC0, it's getting the next behavior tree to set as the new head. The instruction was around a `lock cmpxchg [rsi+00000440],rcx` instruction. So we can just guess the `BehaviorTree` struct layout at least where the next or prev behavior tree pointers are located. You can guess the `prev` pointer offset would be around the `next` pointer offset, at least +/- 0x8 bytes. So I manually checked and it was +0x8 bytes of the `next` pointer offset.

Now, we check what code writes to `a1 + 0x440`. We can set a hardware breakpoint for writing to `a1 + 0x440` and see what code is writing to it, inside Cheat Engine. Since `a1` is a singleton instance, it's always the same address throughout the game session.

Two result came up one where it's popping the head and setting the next behavior tree as the new head, and the other where it's setting the head with some new value here:
```asm
re9.exe+55C71CA - 4B 8B 84 FD E0000000  - mov rax,[r13+r15*8+000000E0]
re9.exe+55C71D2 - 48 89 86 40040000     - mov [rsi+00000440],rax
```

And the function in IDA looks like:

![IDA 2](https://i.ibb.co.com/4nyPcpG2/image.png)

Okay let's focus on this
```c
v10 = *(_QWORD *)(a1 + 0x450) + 0x510 * i;
// ...
v12 = -8i64;
// ...
v13 = *(_QWORD *)(v10 + 8 * v12 + 0xE0);
*(_QWORD *)(a1 + 0x440) = v13;
```

There are other things also going on in this function, but this is where the head of the behavior tree is being set. We don't really have to worry about everything just focus on this bits, let's see what's at `a1 + 0x450`. And whatever the v13 value is when `i` is 0.

For me `*(a1 + 0x450)` is 0x137622630, and if we ignore the `v12` being incremented, the first `v13` value will be `*(0x137622630 + (8*-8) + 0xE0)`, which is 0x118AAFD7C0 for me. And if we use REFramework's ObjectExplorer REObject Inspector:

![ObjectExplorer 2](https://i.ibb.co.com/CsD8n58J/image.png)

So it is indeed a BehaviorTree. Okay let's fast forward and see what writes to `0x137622630 + (8*-8) + 0xE0`, remember it's that `v13` value that eventually gets set at `a1 + 0x440` which is the head of the behavior tree.

So when reloading, loading a save progress, found that:
```asm
re9.exe+56DE84 - 4B 89 14 C2           - mov [r10+r8*8],rdx
```
this is the place where it writes to the `0x137622630 + (8*-8) + 0xE0`(the `v13` value).

Here's the function decompiled in IDA:

![IDA 3](https://i.ibb.co.com/nMwcZ8xq/image.png)

I named:
`mov     eax, [rdx+0D0h]` 0xD0 offset field as `queue_index`.
`movsxd  r14, dword ptr [rdx+40h]` 0x40 offset field as `queue_group`.
`movsxd  r8, dword ptr [rdi+44h]` 0x44 offset field as `index_in_queue`.
Where `rdi`, `rdx` registers contains the address of the BehaviorTree node being removed.

And `a1` is the BehaviorTree handler remember the singleton we were talking about? Which pops the head of the behavior tree and exectues the next behavior tree update.

#### Guessing time...

So from this function and the previous `re9.exe+55C71CA` function which sets `a1 + 0x440` (the head of the behavior tree), we can kind of guess that there are multiple bheavior tree queues, probably some preset by the game developers. Like one for normal animations, one for UI, one for game progress or there could be some other type of behavior tree queues...

So the logic is probably, that there are 8 type of behavior tree queues, each with a different `queue_group` value. Why 8? Remember the `v12` value being set to `-8` in the previous function? That's probably part of the engine's behavior tree queue management logic, hard coded.

Now I think about it(as of writing this post), 
`mov     eax, [rdx+0D0h]` 0xD0 offset field should've been named `queue_group` and 
`movsxd  r14, dword ptr [rdx+40h]` 0x40 offset field as something else...

Actually `v8 = 0x1B0 * [rdx+0x40]` is calculated by the function and later used like this way:
`p_prev = (BehaviorTree **)(v8 + v4 + 0xE0 + 8 * index_in_queue);` Might be some sort of index indicating the "root" behavior tree node in the queue. This gets executed when there is `prev` behaviour tree is null, meaning when the current behavior tree is the first one in the queue.

#### What we've so far

When I say "behavior tree node", I'm kind of talking about BehaviorTreeQueue{ BehaviorTree* node }; that each item of the queue is a node...

* We've guessed that there are 8 type of behavior tree queues, each with a different `queue_group` value probably from 0..8.
* Each behavior tree is also assigned with some sort of index/id/handle? Probably for fast access in the queue.
* A thread maybe switches the behavior tree queue head to switch between different queue heads, maybe a thread local value determines that.
* Then the function `re9.exe+4D16121` calls the execute/update function of the next behavior tree of the current queue head.
* Which eventually calls the actions defined in the behavior tree nodes. Eg. our interested GameJumpAction action.
* And the struct layout for BehaviorTree is:
  - 0x00: The type information
  - 0x08: The ref count
  - 0x0C: padding
  - 0x10: Starts the actual behavior tree data
  - 0x40: Some sort of index or handle for indicating "root" behavior tree node.
  - 0x44: Some sort of index or handle for indicating the current behavior tree node.
  - 0xC0: Next behavior tree node in the queue.
  - 0xC8: Previous behavior tree node in the queue.
  - 0xD0: Some sort index/hanlde to indicate queue group?

#### Reversing the BehaviorTree layout more...

If we go back to the stack return addresses for `*BehaviorTree*GameJumpAction.start`

![stack_return_address 1](https://i.ibb.co.com/LzjzPt6r/image.png)

Let's see which function was called after `re9.exe+4D16121 - FF 90 88000000        - call qword ptr [rax+00000088]`(This one is the 'update'/'execute' function of the behaviour tree, gets called in the game loop/game each frame update)

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

In the function `re9.exe+53AD888`, we can see `mov     r14, [rcx+30h]` instruction where `rcx` is a pointer to a `BehaviorTree`. So at offset 0x30, is the start of this `CoreHandleArray`, btw it's not a pointer to a `CoreHandleArray`, it's directly stored as a value in the `BehaviorTree` struct.

And CoreHandle is defined as:
```c
struct CoreHandle
{
  uint8_t _obj_padding[16];
  void *_padding1;
  Core core;
  uint8_t unknown[40];
};
```

Yes, `CoreHandle` is a "ManagedObject" but the type information doesn't contain anything about the `Core` struct, meaning `Core` is not a "ManagedObject" itself. BTW the struct names are completely arbitary I mean not really, `CoreHandle` is not arbitrary if we check the type information of it, it will show `via.behaviortree.BehaviorTree.CoreHandle`.

Why do I think `Core` is a seperate struct and stored directly in `CoreHandle` as a value, rather than a pointer? Because if you notice function calls like:
`sub_1453AD8F0(&current_handle->core, a2);` or 
```asm
re9.exe+53AD881 - 48 8D 4B 18           - lea rcx,[rbx+18]
re9.exe+53AD885 - 48 89 F2              - mov rdx,rsi
re9.exe+53AD888 - E8 63000000           - call re9.exe+53AD8F0
```
`rbx` is a pointer to the `CoreHandle` struct, and `[rbx+18]` is the `Core` struct within the `CoreHandle` struct. And `lea rcx,[rbx+18]` gets the address of the `Core` struct within the `CoreHandle` struct, the typical equivielnt of `&current_handle->core` and passes it to the `call re9.exe+53AD8F0` function.

And btw this `re9.exe+53AD8F0` function is what calls the `*BehaviorTree*GameJumpAction.start` function, which triggers the next scene transition for in-game progress.

And eventually, if we keep reversing these functions, we can figure out the struct layout of `Core` and how action arg is stored to call `*BehaviorTree*GameJumpAction.start`.

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

If we check further into these functions, the stack return addresses for `*BehaviorTree*GameJumpAction.start`:

![stack_return_address 1](https://i.ibb.co.com/LzjzPt6r/image.png)

We can eventually figure out:

```c
struct __declspec(align(8)) TreeObjectData
{
  uint8_t pad1[176];
  uint32_t some_count;
  uint8_t uknown[512];
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
  uint8_t uknown[768];
};
```

Btw these struct names are completely arbitrary, just made those up whatever made sense to me at the time.

Notice that `TreeObject` has a field called `actions` which contains bunch of `ManagedObjects` similar to our interested `*BehaviorTree*GameJumpAction`.

BTW one more thing about `re9.exe+4D16121 - FF 90 88000000        - call qword ptr [rax+00000088]`(This one is the 'update'/'execute' function of the behaviour tree, gets called in the game loop/game each frame update)

```asm
re9.exe+4D16118 - 48 8B 03              - mov rax,[rbx]
re9.exe+4D1611B - 48 89 D9              - mov rcx,rbx
re9.exe+4D1611E - 48 89 FA              - mov rdx,rdi
re9.exe+4D16121 - FF 90 88000000        - call qword ptr [rax+00000088]
```

`rbx` is the `BehaviorTree` instance pointer.

`mov rax, [rbx]` - moving the "type information", at offset 0x00 is the TypeDefinition pointer, the metadata about the `BehaviorTree` type. There are other fields in there as well but at offset 0x88, there is a function pointer to the 
"update"/"execute" function of the `BehaviorTree`. The point is this type information also contains function pointers flattened along with the type definition and other metadata.

#### Ending...

So in summary, we know how the `BehaviorTree` type information is laid out, how the game calls the "update"/"execute" function, and how a game frame update processes the `BehaviorTree` queue, to execute the `BehaviorTree` actions, one by one.

But we haven't yet called ourselves. If we check the `app.LevelFlowManager` singleton class, and it's field `_ManagedObjectList`:

![LevelFlowManager _ManagedObjectList](https://i.ibb.co.com/SXNgPbT7/image.png)

Each `app.LevelFlowManagedObject` instance is a `via.Component` instance, and each one has a child component with type `via.behaviortree.BehaviorTree`, this is our `BehaviorTree` instance.

How did I get to this point? Well, I used REFramework's plugin capabilities to hook into the `*BehaviorTree*GameJumpAction.ctor` function, remember what `.ctor` does? It's the constructor for the `*BehaviorTree*GameJumpAction` class, and it's called when a `*BehaviorTree*GameJumpAction` is created, since it's a virtual constructor, I had to check if the current `this` pointer type matches the `*BehaviorTree*GameJumpAction` type.

After that I logged the `*BehaviorTree*GameJumpAction` instance address, then I searched for the address in the memory using Cheat Engine, and then reverse searched whoever contains `ManagedArray` which has the `*BehaviorTree*GameJumpAction` instance address. And remember `ManagedArray` is in a `TreeObject`, then I searched for which `Core` instance contains the `TreeObject` instance. And after finding `Core`'s address we can just do `-0x18` to get the `CoreHandle` instance address. After that we search for the `CoreHandle` instance address in the memory using Cheat Engine, and then reverse searched whoever contains the `CoreHandle` instance address -> `CoreHandleArray` -> `BehaviorTree` -> `owner GameObject` and finally look for who also is child of the `owner GameObject`.

And that's it we can get all the `BehaviorTree` instances of current "level" from `app.LevelFlowManagedObject._ManagedObjectList`, and then manually get the Child Component which is a `BehaviorTree` type, and then call the `+0x88` offset "function pointer" to start any `BehaviorTree` instance. But since the multiple threads are also executing different `BehaviorTree` instances, we should start our `BehaviorTree` instance in that thread, to avoid race conditions.

If you need to concrete usage of this `BehaviorTree`, you can check out this [zig example part of my zig_reframework_plugin project](https://github.com/IamSanjid/zig_reframework_plugin/blob/main/src/examples/re9_forced/behavior_tree.zig).
