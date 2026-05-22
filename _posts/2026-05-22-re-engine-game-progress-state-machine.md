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

Now we're kind of stuck since we don't know much about the `*BehaviorTreeAction*.start(via.behaviortree.ActionArg)`, who is calling what logic it's applying to call it...<br>
Time to bring our trusty debugger, Cheat Engine 

