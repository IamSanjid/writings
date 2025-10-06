---
layout: post
title: Decompiling a Kotlin Android App.
subtitle: Android JVM handles Kotlin and Java similarly.
gh-repo: iamsanjid/mybl-balance-viewer
gh-badge: [watch, follow]
tags: [kotlin, java, reverse-engineering, jvm, smail, dex-decompiling]
author: IamSanjid
---

## Final Result
Reverse engineered how [MyBL App](https://play.google.com/store/apps/details?id=com.arena.banglalinkmela.app&hl=en) communicates with the backend, made a simple web-app which applies the idea it. [Live View](https://mybl-balance-viewer.netlify.app/)

{: .box-warning}
**Disclaimer:** Since the reverse engineering parts only shows how the App communicates with the backend and the backend is also officially open for their Web-App, so I think the whole thing is pretty transparent.

# What are we reversing?
This App is called [MyBL](https://play.google.com/store/apps/details?id=com.arena.banglalinkmela.app&hl=en), officially available in PlayStore, and we're going to reverse engineer how it communicates with the backend.

Since it's an App related to SIM, one might think that it must communicate with the SIM card, and perform things according to the SIM-App protocols.
But in reality these Apps needs much more flexibility than what they can get by communicating with the SIM card.

That's why often theese Apps resolve to some other faster way to communicate with the backend. And it's most of the time done through some sort of HTTP backend.

Btw, this is why you'll see these types of Apps not working without any Internet Connection.

#### How do we start?
Alright, we need couple of things, first we need the actual Android Package Kit(APK). One easy way is to download the app on an Android device through PlayStore, then pull
that apk into our laptop or pc using [`adb`](https://developer.android.com/tools/adb).

Then we need to be able to see it's logics, right? Since, it's compiled to something. Usually an Android App can be made using entirely in Kotlin or Java, or some low-level programming language, with some Java/Kotlin bridge.

If an app is made using low-level languages like Rust, C/C++, then we would've to decompile x86_64/armeabi-v7a/arm64-v8a assembly depending on what CPU architecture the App initially supports.

On the other hand, if the App was made using only Kotlin/Java, we will have to decompile JVM Bytecode.

How can we know? Let's use some online available tools which will let us "decompile" APKs, after googling around, I found [jadx](https://github.com/skylot/jadx), [apktool](https://apktool.org/).

`apktool` is sort of "lower-level APK decompiling tool", it doesn't decompile anything, it just extracts files from the APK(it's Zip file at the end of the day) and does some decryption on the extracted files.
Its useful when the App was made in low-level languages, we'd be able to get the `.so` files, which'd contain the App's logic, these are in ELF format(Android is Linux) and we would've been able to decompile them
according to the supported CPU architecture's assembly.

On the other hand, `jadx` is mainly used to decompile Dalvik Executable(DEX), which is the Kotlin/Java's compiled bytecode format. And luckily the App we're trying to reverse-engineer is made entirely in Kotlin.
Well, I don't know if they used any cross-platform mobile app framework like [Flutter](https://flutter.dev/), but the app seemed to be made entirely in Kotlin. But they also have an iOS version, don't know if they
wrote the app twice for two platforms seperately or not.

### JADX for Smooth Sailing
Okay after opening the APK in JADX, we should open `Resources/AndroidManifest.xml`

![AndroidManifest.xml](https://i.postimg.cc/PxhQZf7R/image.png)

This file kind of used to detect the entrypoint, plus shows what kinds of permission the App needs, to work properly. Android Runtime reads it parses every permission stuff and then usually runs an `Activity` class(all the specified class names inside of `<activity>` inherits `Activity` class).
After scrolling, we'll stumble upon the `com.arena.banglalinkmela.app.p020ui.splash.SplashActivity` class name, which overall looked something like this:
```xml
        <activity
            android:theme="@style/SplashTheme"
            android:name="com.arena.banglalinkmela.app.p020ui.splash.SplashActivity"
            android:enabled="@bool/splash_enabled"
            android:exported="true"
            android:screenOrientation="portrait"
            android:windowSoftInputMode="stateAlwaysHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="http"/>
                <data android:scheme="https"/>
                <data android:host="banglalink.net"/>
                <data android:host="www.banglalink.net"/>
                <data android:host="mybl.digital"/>
                <data android:host="www.mybl.digital"/>
            </intent-filter>
        </activity>
```
We're interested in this because of these `intent-filer`(s)
```
<intent-filter>
    <action android:name="android.intent.action.MAIN"/>
    <category android:name="android.intent.category.LAUNCHER"/>
</intent-filter>
```
This `Activity` class will be called upon launch. More information can be found [here](https://developer.android.com/guide/topics/manifest/manifest-intro).

Now if we double click on

![LauncherClass_Click](https://i.postimg.cc/4dNhsYMq/image.png)

`jadx-gui` should open the decompiled class

![SplashClass_First](https://i.postimg.cc/MHHRbnm6/image.png)

After inspecting a little bit, I figured if you really want to understand what the code is doing you should switch to `Simple` mode from bottom left corner.

![Simple-View](https://i.postimg.cc/13GgF0ZZ/image.png)

Otherwise `Code` view is fine for getting overall idea.

Okay a lot of mangled variable names... Let's perform basic reverse-engineering technique, search for known String!

### Setting goal...
Well since the App is entirely made in an interpreted language, and also not protected other than maybe some level of obfuscation... If we wanted we could fully reverse-engineer every aspect of the App.
But for this blog post and simplicity we will only reverse engineer the parts to know how the App sign-ins a new user and how it gets the balance summary.
### Grinding...
So, it's an App related to SIM, so something called OTP should be there right? From top menu bar `Navigation/Text Search`

![TextSearch](https://i.postimg.cc/gch6dbBz/image.png)

Okat now let's search for `"otp`(`"` because some Java/Kotlin `String` might be using it) then after selecting all the check boxes `Class`, `Method`, `Field` ... and pressing `Load all` button should search for every place where `"otp` exists.
Immidiately something interesting was found:

![FirstSearch](https://i.postimg.cc/PqBrFPHx/image.png)

After double clicking it, `AuthenticationApi` class was opened:

![AuthApi_Class](https://i.postimg.cc/7LqNJYdT/image.png)

```Java
    public final o<LoginSuccessfulResponse> verifyOtp(VerifyOtpRequest otpRequest) {
        C6779y.checkNotNullParameter(otpRequest, "otpRequest");
        return e.onResponse(this.service.verifyOtp(otpRequest));
    }
```
After inspecting the method, we can see `this.service.verifyOtp` is being called..
Double clicking on `verifyOtp` method it opened the `AuthenticationService` interface.

![AuthService_Class](https://i.postimg.cc/fR1NMprq/image.png)

And we see some `api/v2/verify-otp` API endpoints! So, yeah they're sending HTTP requests to communicate with the backend.
After looking at the imported package names they're using [`retrofit`](https://github.com/square/retrofit) HTTP Client library.
And some annotations magic is happening in this interface.

This interface is in `com.arena.banglalinkmela.app.data.datasource.authentication` package, let's inspect the parent packages. From the `Source Code` tree view from left side.

![Package_Tree](https://i.postimg.cc/MT2ffsn2/image.png)

Looks like most of the HTTP request/response level classes/interfaces are in this package.
Let's find the Base URL. Let's see how we can find who's using some class, let's say we wanna find everything, which are using the `AuthenticationApi` class, select the class name right click and click `Find Use` something like this should show-up:

![Class_Ref1](https://i.postimg.cc/NfzMrNnS/image.png)

Okay now let's "Find Use" for `AuthenticationService` and some class's method is doing something like this:
```Java
return (AuthenticationService) V.instance.getRestApiClient(context, session).createService(AuthenticationService.class);
```
Let's double click on `getRestApiClient` and volla we find the place where it seems some HTTP client is being created? But more importantly we find the Base Url:
```Java
    public final net.banglalink.android.core.api.a getRestApiClient(Context context, Session session) {
        C6779y.checkNotNullParameter(context, "context");
        C6779y.checkNotNullParameter(session, "session");
        return net.banglalink.webservice.f.f52185c.getInstance("https://myblapi.banglalink.net/", net.banglalink.webservice.g.f52189c.getInstance(getRefreshTokenRepository(context, session)), getAppCache(context), C6742s.listOf((Object[]) new okhttp3.A[]{net.banglalink.webservice.interceptors.f.f52203b.getInstance(getAppCache(context)), net.banglalink.webservice.interceptors.a.f52192b.getInstance(getUserDataProvider(context, session)), net.banglalink.webservice.interceptors.c.f52197b.getInstance(getUserDataProvider(context, session)), net.banglalink.webservice.interceptors.d.f52200b.getInstance(EntitlementProviderImpl.Companion.getInstance(session)), OkHttpLoggerImpl.Companion.getInstance().mo7010getLoggingInterceptor(), ChuckerLoggerImpl.Companion.getInstance(context).mo7010getLoggingInterceptor()}), kotlin.collections.r.listOf(net.banglalink.webservice.interceptors.b.f52195a.getInstance()));
    }
```

Okay, now how do we distinguish which are `GET` which are `POST` requests?
Well from name we can guess which are which, but we can also try to brute-force.

For brute-forcing I will be using JavaScript Node.js runtime.

Let's try with this interface method found in `AuthenticationService`:
```Java
    @k({"Cache-Control: no-cache"})
    @f("api/v1/otp-config")
    o<w<OtpConfigResponse>> getOtpConfig();
```

So we can tell that `@k` can accept HTTP Request Header, and from the name we can tell, this method might be sending `GET` HTTP method.

Let's define some `test.mjs`(.mjs to load it as module script) and put some code:
```JavaScript
const BASE_URL = "https://myblapi.banglalink.net/";

const API_GET_OPT_CONFIG = "api/v1/otp-config";

async function getOtpConfig() {
  let resp = await fetch(`${BASE_URL}${API_GET_OPT_CONFIG}`, {
    method: 'GET',
    headers: {
      'Cache-Control': 'no-cache',
    },
  });
  return await resp.json();
}

async main() {
  console.log(await getOtpConfig());
}
main();
```

And after `node test.mjs` it seems to be a valid HTTP Request for the `myblapi` backend.

So `@f` or `@retrofit2.http.f` annotations are mainly for `GET` HTTP method.
And `@o` or `@retrofit2.http.o` annotations are mainly for `POST` HTTP method.

Okay now let's check this interface method located in `AuthenticationService`:
```Java
    @retrofit2.http.o("api/v2/verify-otp")
    o<w<LoginSuccessfulResponse>> verifyOtp(@a VerifyOtpRequest verifyOtpRequest);
```

After inspecting(double clicking on the class name) `VerifyOtpRequest` 

![VerifyOtpRequest_1](https://i.postimg.cc/DfYFCSc2/image.png)

We need to some `client_id` and `client_secret`...

Let's go see who uses this `VerifyOtpRequest` like before.
The constructor looks like this:
```Java
    public VerifyOtpRequest(String otpToken, String str, String str2, String otp, String str3, String str4, String username, String str5, int i2, C6771p c6771p) {
        this((i2 & 1) != 0 ? "" : otpToken, (i2 & 2) != 0 ? "otp_grant" : str, (i2 & 4) != 0 ? "users" : str2, (i2 & 8) != 0 ? "" : otp, (i2 & 16) != 0 ? BuildConfig.CLIENT_SECRET : str3, (i2 & 32) != 0 ? BuildConfig.CLIENT_ID : str4, (i2 & 64) != 0 ? "" : username, (i2 & 128) != 0 ? "" : str5);
    }
```

Which sets some default values from `BuildConfig.CLIENT_SECRET` and `BuildConfig.CLIENT_ID`
And this is the `BuildConfig` class:

![BuildConfig](https://i.postimg.cc/zGZsMKHN/image.png)

BTW, an interesting thing, this is how the constructor of `VerifyOtpRequest` is called:
```Java
new VerifyOtpRequest(str, null, null, otp2 == null ? "" : otp2, null, null, mobileNumber, null, 182, null)
```
Notice a magic number `182`? Either Kotlin/Java compiler under the hood handles *default* values this way, or this is some compile-time generated code maybe through annotations.

Anyways, we can deduce the `api/v2/verify-otp` endpoint's request and write something like this:
```JavaScript
const BASE_URL = "https://myblapi.banglalink.net/";
const CLIENT_SECRET = "NUaKDuToZBzAcew2Og5fNxztXDHatrk4u0jQP8wu";
const CLIENT_ID = "f8ebe760-0eb3-11ea-8b08-43a82cc9d18c";
/* ... */
const API_VERIFY_OTP = "api/v2/verify-otp";

/* ... */
async function verifyOtp(otpToken, otp, username) {
  const body = {
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    grant_type: 'otp_grant',
    otp: otp,
    otp_token: otpToken,
    provider: 'users',
    request_type: '',
    username: username,
  };

  let resp = await fetch(`${BASE_URL}${API_VERIFY_OTP}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  return await resp.json();
}
```

And through `Find Use` method I found that most of the times "phone number" is passed as `username` field.

Let's check one more interface method of `AuthenticationService`:
```Java
    @retrofit2.http.o("api/v1/send-otp")
    @e
    o<w<OtpResponse>> sendOtp(@retrofit2.http.c("phone") String str);
```
From `@retrofit2.http.o` annotation we can guess this is also a `POST` HTTP method, and I will be guessing that `@retrofit2.http.c("phone")` annotation means a json object will be created with a field named `phone`, as most of the reuquests we encounter are sending json objects.

So JS code would be something like:
```JavaScript
/* ... */
const API_SEND_OTP = "api/v1/send-otp";
/* ... */
async function sendOtp(phone) {
  const body = {
    'phone': phone,
  };
  let resp = await fetch(`${BASE_URL}${API_SEND_OTP}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  return await resp.json();
}
```

This is the complete version I glued together after following the similar "Find Use" feature of `jadx`:
```JavaScript
import readlinePromises from 'node:readline/promises';

const BASE_URL = "https://myblapi.banglalink.net/";
const CLIENT_SECRET = "NUaKDuToZBzAcew2Og5fNxztXDHatrk4u0jQP8wu";
const CLIENT_ID = "f8ebe760-0eb3-11ea-8b08-43a82cc9d18c";

const API_GET_OPT_CONFIG = "api/v1/otp-config";
const API_SEND_OTP = "api/v1/send-otp";
const API_VERIFY_OTP = "api/v2/verify-otp";
const API_REFRESH_TOKEN = "api/v1/refresh";
const API_GET_USER_PROFILE = "api/v1/customers/details";
const API_GET_BALANCE_SUMMARY = "api/v1/balance/summary";
const API_GET_BALANCE_DETAILS = "api/v1/balance/details/all";

async function getOtpConfig() {
  let resp = await fetch(`${BASE_URL}${API_GET_OPT_CONFIG}`, {
    method: 'GET',
    headers: {
      'Cache-Control': 'no-cache',
    },
  });
  return await resp.json();
}

async function sendOtp(phone) {
  const body = {
    'phone': phone,
  };
  let resp = await fetch(`${BASE_URL}${API_SEND_OTP}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  return await resp.json();
}

function extractOtp(text, otpConfig) {
  const pattern = new RegExp(`(|^)\\d{${otpConfig.token_length}}`);
  const match = text.match(pattern);
  if (match === null) return null;
  if (Array.isArray(match)) return match[0];
  return match;
}

async function verifyOtp(otpToken, otp, username) {
  const body = {
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    grant_type: 'otp_grant',
    otp: otp,
    otp_token: otpToken,
    provider: 'users',
    request_type: '',
    username: username,
  };

  let resp = await fetch(`${BASE_URL}${API_VERIFY_OTP}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  return await resp.json();
}

async function getTokenUsingRefreshToken(token) {
  const body = {
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    grant_type: 'refresh_token',
    refresh_token: token,
  };

  let resp = await fetch(`${BASE_URL}${API_REFRESH_TOKEN}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  return await resp.json();
}

function getToken(token) {
  return token.token_type + " " + token.access_token;
}

async function getUserProfile(token) {
  let resp = await fetch(`${BASE_URL}${API_GET_USER_PROFILE}`, {
    method: 'GET',
    headers: {
      'Authorization': token,
    },
  });
  return await resp.json();
}

async function getBalanceSummary(token) {
  let resp = await fetch(`${BASE_URL}${API_GET_BALANCE_SUMMARY}`, {
    method: 'GET',
    headers: {
      'Authorization': token,
    },
  });
  return await resp.json();
}

async function getBalanceDetails(token) {
  let resp = await fetch(`${BASE_URL}${API_GET_BALANCE_DETAILS}`, {
    method: 'GET',
    headers: {
      'Authorization': token,
    },
  });
  return await resp.json();
}

async function main() {
  const rl = readlinePromises.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  try {
    const otpConfig = (await getOtpConfig()).data[0];

    const phoneNumber = await rl.question('Phone Number: ');

    const sentOtp = (await sendOtp(phoneNumber)).data;

    const otpInput = await rl.question('OTP: ');
    const otp = extractOtp(otpInput, otpConfig);

    const tokenAndUserInfo = (await verifyOtp(sentOtp.otp_token, otp, phoneNumber)).data;
    console.log(tokenAndUserInfo);

    const token = (await getTokenUsingRefreshToken(tokenAndUserInfo.token.refresh_token)).data;
    console.log(token);

    const authToken = getToken(token);
    const customer = (await getUserProfile(authToken)).data;
    const is_postpaid = customer.is_postpaid !== undefined && customer.is_postpaid === true;
    console.log("Is postpaid: ", is_postpaid);

    const balanceSummary = (await getBalanceSummary(authToken)).data;
    console.log(balanceSummary);

    const balanceDetails = (await getBalanceDetails(authToken)).data;
    console.log(balanceDetails);

  } catch (error) {
    console.error('An error occurred:', error);
  } finally {
    rl.close();
  }
}

main();
```

`node test.mjs` should be enough. The above code was glued together by checking `AccountService`, `AccountBalanceSummeryService`, `AuthenticationService`, `RefreshTokenService` interfaces and their methods in `com.arena.banglalinkmela.app.data.datasource.*` package, with the help of `jadx`'s "Find Use" feature.


The MyBL App uses MVP architectural pattern, so a lot of interface glue type code is generated during compilation, but if we look hard enough with proper motivation we can find our interested logic parts easily.

