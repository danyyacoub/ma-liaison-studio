# Ma Liaison Studio

An iPhone app for Ma Liaison: put a price on outlet photos and videos, style it, animate it, and send it to Instagram Stories, TikTok or WhatsApp.

Everything runs on the phone. Photos and videos are never uploaded.

There are two ways to run it:

- **iPhone app** (recommended): opens Instagram's Story editor directly with the finished photo or video, saves to Photos, and exports videos quickly.
- **Web app**: open https://danyyacoub.github.io/ma-liaison-studio/ in Safari, tap Share, then **Add to Home Screen**. No Mac needed, but Instagram Stories takes one extra step.

## Install the iPhone app (on a Mac)

You need a Mac, a USB cable for the iPhone, and an Apple ID.

1. Install **Xcode** from the Mac App Store and open it once so it finishes setting up.
2. Install **Node.js** (the LTS version) from https://nodejs.org.
3. Download this project: on GitHub tap **Code → Download ZIP** and unzip it, or run
   `git clone https://github.com/danyyacoub/ma-liaison-studio.git`.
4. In Terminal, go into the folder and run:
   ```
   npm install
   npm run ios
   ```
   Xcode opens with the app.
5. In Xcode, click **App** in the left sidebar, then **Signing & Capabilities**. Tick **Automatically manage signing** and pick your Apple ID under **Team** (add it with **Add an Account…** if needed). If Xcode says the bundle id is taken, change `com.maliaison.studio` to something unique, like `com.maliaison.studio.dany`.
6. Plug in the iPhone, unlock it, and choose it at the top of Xcode. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode** if asked and restart.
7. Press the ▶ button. The first time, the iPhone will refuse to open the app: go to **Settings → General → VPN & Device Management**, tap your Apple ID and **Trust**.

With a free Apple ID the app stops opening after 7 days. Plug the iPhone in and press ▶ again to renew it. A paid Apple Developer account ($99 a year) makes it last a year and allows installing through TestFlight without a cable.

### Instagram app id (optional, recommended)

Instagram asks apps that open its Story editor to say who they are. Create a free app at https://developers.facebook.com/apps (type **Other → Business**), copy its **App ID**, and put it in `src/app.html`:

```js
const META_APP_ID = '1234567890';
```

Then run `npm run ios` again and press ▶.

## Changing the app

- The editor is `src/app.html`. The iPhone-only parts (Instagram Stories, saving to Photos, video export) are in `ios/App/App/MaLiaisonPlugin.swift`.
- `npm run build` (or `sh build.sh`) writes `index.html` for the web app and `www/index.html` for the iPhone app.
- For the web app, bump `VERSION` in `sw.js` and push to `main`; GitHub Pages publishes it.
- For the iPhone app, run `npm run ios` and press ▶ in Xcode.
