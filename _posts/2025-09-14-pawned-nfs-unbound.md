---
layout: post
title: Reverse engineering a modern Car game.
subtitle: From creating a simple assembly detouring tool to reversing some part of a game.
gh-repo: iamsanjid/pawnednfsunbound
tags: [zig, reverse-engineering, x86_64, assembly]
author: IamSanjid
---

## Achievements
Reversed engineered how the game initializes the resources, a basic idea of the game's resource handling mechanism, found a clear path how we can add/modify/delete resources.

1. All normal story mode races are available everyday in single player. (They're apparently not.)
2. Copy one car's performance stats to another car.
3. Unlocked most of the items. (Cars, Bodykits, Visuals)

{: .box-warning}
**Disclaimer:** I do not condone any form of cheating where it would degrade other people's experience. This repository/blog doesn't directly show anything which would benefit an user in-game online activities.

# The start
The initial goal was to write some sort of "hooking" framework in [Zig](https://ziglang.org/) to learn more about it's [comptime](https://ziglang.org/documentation/master/#comptime), [build system](https://ziglang.org/learn/build-system/) and [inline assembly](https://en.wikipedia.org/wiki/Inline_assembler) capabilities. For this I had to choose something relatively modern yet "easy" to perform basic reverse-engineering. And, at the time I was playing some [Need for Speed Unbound](https://store.steampowered.com/app/1846380/Need_for_Speed_Unbound/). So, the choice was obvious but there is another reason for choosing it...

So, this game got different classes of cars, D to S+, higher class cars were faster and lower class cars were slower, it also got different types of race, in some races you would prefer cars with better top-speed, in some better acceleration, in some better cornering and so on.

But I had one issue with the game's balancing system my favourite Need for Speed franchise car [BMW M3 GTR E46](https://www.bmw-m.com/en/topics/magazine-article-pool/bmw-m3-gtr-need-for-speed-most-wanted.html) was not best in any of those classes in any of those race types, but the Audi R8 was considered sort of "best" in most of the race types at A+ and S classes. So, as a BMW M3 GTR fanboy I wasn't happy :).

Clear goal in-mind, I need to either make BMW M3 GTR perform "better" or at least perform as good as Audi R8. Since, I was kind of feeling lazy I just chose the easier path copying the "handling" stats of the Audi R8 and put it into my beloved BMW M3 GTR's handling. I didn't want to think about the game's physics, that's why I didn't choose making the car perform better route.

### Okay then...?
First, we need to somehow view the x86_64 assembly also a debugger would be great with it. I was thinking about using [x64dbg](https://x64dbg.com/) but then I thought Need for Speed Unbound's "minimal anti-cheat" might detect its default debugging techniques. So, I chose [CheatEngine](https://www.cheatengine.org/) 7.4 version!

Yeah... CheatEngine comes with pretty decent x86_64 disassembler and debugging options. I configured CheatEngine to (ab)use Microsoft's (C++) exception handling mechanism also kind of known as [VEH](https://en.wikipedia.org/wiki/Microsoft-specific_exception_handling_mechanisms#Vectored_Exception_Handling) debugging. One can enable it by going to "Settings" -> "Debugger Options" of CheatEngine(CE).

![Debugger Options]({{ '/assets/img/pawned-nfs-unbound/ce_dbg_settings.png' | relative_url }})


Okay I will have to make some confession. I didn't completely reverse-engineer all the things on-my-own, it would've taken a lot of time. I used a fork of [FrostyToolSite](https://github.com/HarGabt/FrostyToolsuite/), a tool which can dump/inspect resources of the games made by using the [Frostbite](https://www.ea.com/frostbite) Game Engine. I mainly used it to find the resource structure, like how a car's engine data is stored, what kind of data makes of the full engine data etc.. It was a lot of C++ OOP Inheritence crapload.

![FrostyToolsuite Editor]({{ '/assets/img/pawned-nfs-unbound/frosty_editor_1.png' | relative_url }})

### Start the Reverse-Engineering...
*The offsets discussed below might get changed for future version of the game, if an update ever comes, but the process of obtaining them should be similar.*

Our plan is to find the the function/x86_64 assembly code which initializes the resources to make them mutable by other the game logic codes. At, first I thought of searching for string literals. I mean the game must need to process at string level, and render them accordingly, everything cannot be a texture or an image right? But it was taking a lot of time to figure out, so I thought of a different approach.

You see all the resources of the Frostbite Engine is assigned with a [GUID](https://learn.microsoft.com/en-us/windows/win32/api/guiddef/ns-guiddef-guid)

![Guid Showcase]({{ '/assets/img/pawned-nfs-unbound/frosty_editor_guid.png' | relative_url }})

So according to [Microsoft GUID definition](https://learn.microsoft.com/en-us/windows/win32/api/guiddef/ns-guiddef-guid) it's layed out like this:
```cpp
typedef struct _GUID {
  unsigned long  Data1;
  unsigned short Data2;
  unsigned short Data3;
  unsigned char  Data4[8];
} GUID;
```
And `sizeof(GUID)` is 16 bytes long. It means we could just search for 0x10 bytes long array and we should be near a place where the our desired resource data is layed out in memory. We can basically obtain our desired resource's GUID from the FrostyToolsuite and search for it!

CE has a feature to search for AOB(array of bytes), so let's search for AUDI R8 Engine Config Resource.
```
The GUID: {64efb502-6271-4b56-a732-f690fce6a766}
In Hex Bytes Form: 02 b5 ef 64 71 62 56 4b a7 32 f6 90 fc e6 a7 66
```

I searched for it when I was in in-game story-mode, when all the story-mode related resources have been loaded.

Well, at first I found couple of addresses, like the typical concrete address finder I just did some different in-game stuff like going to online mode, story mode...

One of the address should contain it consistently since it's related to resource. So after going in-n-out to online and story mode, I found one address which surroundings looked like this(In Default settings after selecting the address Ctrl+B shows the memory region it's in):

![GUID-InMemory]({{ '/assets/img/pawned-nfs-unbound/ce_guid.png' | relative_url }})

Well, we can ignore those 0x10 bytes as we know it's the GUID, but what are the rests? After scrolling a little bit I found:

![Resource-Name]({{ '/assets/img/pawned-nfs-unbound/ce_resource_name.png' | relative_url }})

So, we can kinda be sure that we're at the right place, right?

Let's check FrostyToolsuite what does a Engine Config Resource Structure look like.

![Engine-Config-Data]({{ '/assets/img/pawned-nfs-unbound/frosty_editor_engine_conf.png' | relative_url }})

Okay let's take a step back, the tool is showing the data structure nicely but how do we interpret our original memory bytes to those data types?

Here comes CE our saviour once again, it can guess field types for different memory addresses as if they were some structure. Tools -> Dissect data/structures

![Dissect-Structure]({{ '/assets/img/pawned-nfs-unbound/ce_dissect.png' | relative_url }})

After that we need to put the address we found by searching resource GUID, we're putting `<Address> + 0x10`(in the image 10 interprets as 0x10 just some CE things) since there is nothing to guess about the GUID right? Structures -> Define New Structure, we want CE to guess data types of 2048(just a good number to start) bytes from our desired addresse.

![Dissect-Addr]({{ '/assets/img/pawned-nfs-unbound/ce_dissect_addr.png' | relative_url }})

The dissect first look:
![Dissect-First]({{ '/assets/img/pawned-nfs-unbound/ce_dissect_first.png' | relative_url }})

I can see some floats, the offset 0x50 value matches our `EngineResistance` field's value(in the FrostyToolsuite we can see the values). We're definitely looking at the right place that's for sure just data type guesses are wrong, like there should be a `Float` at 0x40 offset since there are 4 `Float` fields before our `EngineResistance` field, and I think at 0x3C offset there shouldn't be any `Double` field. How can I tell about these? I am just matching the data structure and values the FrostyToolsuite is showing. 

Okay let's remove the 0x3C offset value and add a `Float` data type at 0x40 offset.

![Delete-Data]({{ '/assets/img/pawned-nfs-unbound/ce_dissect_delete.png' | relative_url }})

Now a add new `Float` data type at 0x40 offset

![Add-Data]({{ '/assets/img/pawned-nfs-unbound/ce_dissect_add.png' | relative_url }})

Usually `Float`s are considered 32 bits or 4 bytes we're just going to follow that. And since FrostyToolsuite is showing some data type as `List<...>` we're going to treat them as some pointer which are probably used to point to an array/list-like data.

Since we're dealing with C++ class concept(just some educational guesses) first 16 bytes(not talking about GUID, 8 bytes + 8 bytes) should represent a pointer to the [VFTable](https://en.wikipedia.org/wiki/Virtual_method_table) and next 8 bytes should be a pointer pointing to some sort of resource metadata/object metadata?(just guessing)

Actually if you look at the memory region the bytes representation perfectly aligns for two pointers. Many of the times if some data doesn't make sense as normal primitive type, there is a high chance they might look sensible as pointers.

This is how the cleaned version looks like:

![Dissect-Cleaned]({{ '/assets/img/pawned-nfs-unbound/ce_dissect_clean.png' | relative_url }})

Hey even 0x18 offset is pointing to a string or basically acting as `char *`. Our resource name!

![Dissect-String]({{ '/assets/img/pawned-nfs-unbound/ce_dissect_str.png' | relative_url }})

So, we can conclude something like this:<br>
```
[GUID - 0x10 bytes]
Start->[VFTable Pointer]
Start+0x8->[Metadata]
Start+0x10->[...8bytes Unknown]
Start+0x18->[ResourceName]
Start+0x20->[....Rest of the data ...]
```

### Found resource memory region! Next...

Okay now we've found the our desired resource's memory region, now we've to find which x86_64 assembly instructions read/write to that region.

How can we do that? Access Breakpoint, basically CE uses CPU specific mechanism/software based simulation(readonly page fault exception handling) to detect which instructions are responsible for reading/writing to our specified memory region. From address list right click -> "Find what accesses this address".

![Addr-Access]({{ '/assets/img/pawned-nfs-unbound/ce_addr_access.png' | relative_url }})

I would like to skip some tedious steps. First thing, I was checking which instructions accessed the GUID memory region, only the `memcpy` function did that, didn't want to go into that rabbit whole. So, I should've been checking for `<GUID-Address> + 0x10` address's access. After wasting some time, couple of instructions accessed the `VFTable Pointer` address(calculated at `<GUID-Address> + 0x10`).

Tedious Steps:
- Get another resource's GUID, find the proper memory region the same way we did for the Audi R8's `EngineConfig` resource.
- Do the "Find what accesses this address" on `<GUID-Address> + 0x10`, keep the instruction addresses which matches with our previous iteration.
- Repeat, until a generic instruction address is found which accesses the `VFTable Pointer` for all the resources.

So, yeah after 30 minutes of repeatition found this address: `NeedForSpeedUnbound.exe + 0x25A1737`.

The base module address of the executable + 0x25A1737 offset the  x86_64 assembly looks like `mov rdx,[rsi]` at that address.

The `rsi` register contains the resource's memory region start address at that point of the execution(some other assembly instructions before this sets `rsi` to the resource's start address).

So `rsi` basically points to the `VFTable Pointer`. And that instruction is reading 0x8 bytes value stored in that address(`rsi`) or the `VFTable Pointer` and storing it to `rdx` register, `rdx` is now the `VFTable Pointer`.

By reading the bytes pointed by `rdx` the other assembly instructions can access to the `VFTable`.

# Arc 2
Okay, at this point I should also talk a little about how we'll be using Zig. We will be following detour hooking mechanism to insert our custom Zig land code.

In-Short Detour hooking is:
- Inserts jump instruction `JMP <ADDRESS>` at specific memory address by replacing some original x86_64 instructions. The address will be our own Zig function address.
- After our own Zig function address needs to return it will simply go back to the original instructions(those should be copied to somewhere else before replacing them).
- Then jumps back to the next instruction, the instruction which should've executed next after the original instructions we replaced with for our JMP instruction.

I will be writing about how I implemented this whole detour hooking mechanism in Zig in future.

### Inserting our code...
Finally, we're here.

So far we've got:
- Reverese-Engineered how resources are generally layed out in memory.
- Found an address where instructions accesses those resources to mutate them, probably.

Now, let's remind ourselves about the goal, we want to copy Audi R8's performance stats to BMW M3 GTR, so in order for us to do that we need to first find those performance stats related resources then copy them byte by byte to the BMW M3 GTR's performance stats resources.

Since a lot of testing was needed here's the plan:
- First we inject a loader dll, how to inject? We can use CE's built-in DLL injector. Most likely uses `CreateRemoteThread` Win32 API to create a *remote* thread on the foreign/target executable context, then run `LoadLibrary` Win32 API to load our loader dll on the foreign executable context.
- This loader dll will then load/unload our custom code dll, this way we will have some sort of hot reloading capabilities.

So, after all those loading, we are in the `NeedForSpeedUnbound.exe` context, meaning we can call `GetModuleHandle` Win32 API get the module base address, this base address is basically the address in RAM where the OS has loaded the .exe.

So after getting the base address we can just add `0x25A1737` and we will get our desired location to perform detour hooking.

But we've to access `rsi` register... In relatively higher level language than assembly like Zig we cannot access registers directly, right? Unless we use [inline assembly](https://en.wikipedia.org/wiki/Inline_assembler) feature of Zig.

So the plan is we will write raw x86_64 assembly to store all the register values of x86_64 CPU architecture to a specific memory region.

We can use the stack:
```
push %rsp
push %rax
push %rbx
push %rcx
...
mov %rsp, %rcx ; %rcx for windows, %rdi for unix-like system
call ourZigFunction
... ; it's reversed coz we're popping from the stack..
pop %%rcx
pop %%rbx
pop %%rax
pop %%rsp
```

Or we can use `call malloc` and use `mov` instruction to store the register states on the heap. More details can be found in [CopyRaceVehicleConfig.zig](https://github.com/IamSanjid/PawnedNFSUnbound/blob/f2b3028dc18e46c2b0432079763c256f6ddc79f1/src/hooks/CopyRaceVehicleConfig.zig#L1081).

Then we will pass that memory region's start address as pointer, to a normal Zig function. That Zig function can modify that memory region accordingly, then when it returns we can restore the register values from that memory region. In this way we can easily access registers.

- Store register states to a memory region.
- Get the start address of that memory region, call a normal Zig function using `call` inline assembly instruction, we can pass that pointer via `rcx`(Windows) or `rdi`(Unix-like).
- Return from normal Zig function.
- Restore the register states by reading from that memory region.
- Continue with Detour hooking.

Again, I would like to talk about this in more details in one of my future blog.

### Continueing...
If you can read Zig checkout this [CopyRaceVehicleConfig.zig](https://github.com/IamSanjid/PawnedNFSUnbound/blob/f2b3028dc18e46c2b0432079763c256f6ddc79f1/src/hooks/CopyRaceVehicleConfig.zig#L1081) and [nfs_unbound_sdk.zig](https://github.com/IamSanjid/PawnedNFSUnbound/blob/f2b3028dc18e46c2b0432079763c256f6ddc79f1/src/hooks/nfs_unbound_sdk.zig#L1).

Okay we can access registers, we can inject and execute our custom Zig code when the resources gets "initialized"/"accessed" by the game's logic.

Time to perform copying!

So first we need to find out which resources needs to be copied.

- RaceVehicleConfigData -> Basically has pointers to all chunk performance parts, like Engine, Chasis, Aerodynamics Config etc.
- RaceVehicleItemData -> We need copy some part to make certain upgradeable "performance" section match with Audi R8.
- EngineStructureItemData -> We're actually copying this from MustangBoss 302 1969, why? That engine can equipped by Audi R8 but not by BMW M3 GTR.
- FrameItemData -> For upgrade section basically.
- DriveTrainItemData -> Same for upgrade section.

Basic idea is we can use GUID or Resource Name to identify which resource we are getting first.

Say the game is accessing BMW M3 GTR's resource first, we store them in our internal Zig land buffer and set state that we're waiting for Audi R8's resources or Mustang's resources. And we copy them byte by byte later when we encounter them.

And it's done :).

### One more thing...
Since we're using Zig land buffer, we need to reset it whenever we can, otherwise we might get a huge memory leak issue.

But how can we know when to reset it? Alright this time we can do is find out in which place the loading screen texture is being used. There should one root place right?

So, like before we get the loading screen texture resource's GUID, find the resource address, and by using "Find what accesses this address" method like before we try to find where it's being used and found an address which seemed safe enough, was being executed mostly once when loading scene appeared. `NeedForSpeedUnbound.exe+220FA36` is the address.

# Demo
<div style="padding:56.25% 0 0 0;position:relative;"><iframe src="https://player.vimeo.com/video/1118433309?badge=0&amp;autopause=0&amp;player_id=0&amp;app_id=58479" frameborder="0" allow="autoplay; fullscreen; picture-in-picture; clipboard-write; encrypted-media; web-share" referrerpolicy="strict-origin-when-cross-origin" style="position:absolute;top:0;left:0;width:100%;height:100%;" title="PawnedNFSUnbound-Demo"></iframe></div><script src="https://player.vimeo.com/api/player.js"></script>