# Set up Phlix Camera Upload with an AI agent

**For you, the owner of the server.** This file tells an AI coding agent how to install Phlix Camera Upload, the helper that receives camera uploads from the Phlix app. Camera Upload is a beta feature of Phlix 1.0.21 or later. The setup guide for people, with pictures: https://phlixapp.com/camera-upload/

1. Put this file on your server, or on a computer that can reach the server over SSH.
2. Open your AI coding agent in the folder that holds this file, and say: `Follow SETUP-WITH-AI.md`.
3. Answer its questions until it says it is done. The agent asks before it changes anything outside the helper's own folder.

---

Everything below is for the AI agent.

## Goal

Install Phlix Camera Upload in Docker on the machine that runs the owner's Plex Media Server. The helper must write uploads into a folder that is inside a Plex photo library.

The owner is the person you are talking to. Phlix is an app for iPhone and iPad that shows the photos of a Plex Media Server. The helper receives the photos and videos that Phlix uploads from the phone's camera roll over the home network, and writes them into one folder. Plex then shows them. In the app, Camera Upload is marked Beta.

If you cannot run commands on the server yourself, work through the owner. Give them one command at a time, ask them to paste what it printed, and go on from there. Never ask for a Plex token or for the pairing code.

What the owner asks for decides which part you follow:

- To install or set up the helper: follow [Steps](#steps), from Step 1 to Step 11.
- To fix something that does not work: go to [Troubleshooting](#troubleshooting).
- To update the helper: go to [Update](#update).
- To remove the helper: go to [Remove](#remove).

## Done means

An install is done when all of these are true:

1. The container `phlix-camera-upload` runs, and Docker reports it `healthy`.
2. `curl -sk https://localhost:7459/api/v1/hello` answers with `"service":"phlix-camera-upload"`.
3. The helper's own check, `doctor`, ends with `Nothing needs fixing.`
4. The status page says `Upload folder` is `Ready`.
5. The status page says `Plex Media Server` is `Found`, or you told the owner that phones must pair with the pairing code.
6. The upload folder is inside a folder of a Plex photo library. The owner confirmed the folder.
7. Another device on the home network can open `https://SERVER_ADDRESS:7459`.
8. You gave the owner the closing message from Step 11.

## Rules

Follow these rules in every step.

1. Ask before every change outside the install folder. Say what you will change and wait for a yes. Pulling the image and starting the container are the job itself, and need no extra question.
2. Never change Plex. Do not change its settings, its container, its libraries or its files. Do not restart it.
3. Never read Plex's secrets. Do not open `Preferences.xml` or anything else in Plex's own data folder. Do not read or print a Plex token or a claim token. Do not call the Plex API with a token. Run `docker inspect` on the Plex container only with the `--format` values given in this file, because the full output can hold a claim token.
4. Never expose the helper to the internet. Do not forward a port on the router. Do not set up a tunnel, a public reverse proxy or a public DNS name for it.
5. Do not use `sudo` without asking. Ask once for `docker` commands if Docker needs it. Ask again for each other command.
6. Do not show the pairing code unless the owner asks for it. The helper's log holds the code, so read the log only with the command in Step 8, which leaves that line out. Never write the code or a token into a file.
7. Never delete, move or change a file in the owner's photo folders. The only thing you make there is the upload folder, after the owner says yes.
8. Do not install or update Docker or any other software. If something is missing, stop and tell the owner.
9. Use the names, the image, the port and the Compose file exactly as this file gives them. Add a setting only where this file tells you to. Do not set `TLS` to `off`: Phlix talks HTTPS only, and `off` is only for a helper behind the owner's own HTTPS reverse proxy.
10. Stop and ask when you are unsure, and when something looks different from what this file expects.

## Facts

| Fact | Value |
| --- | --- |
| Image | `ghcr.io/jrl8085/phlix-camera-upload:1` |
| Container name | `phlix-camera-upload` |
| Port | TCP 7459, HTTPS with a certificate the helper makes itself |
| Upload folder inside the container | `/photos` |
| Helper's own data inside the container | `/config` |
| Install folder | `phlix-camera-upload` in the home folder of the user on the server |
| Status page | `https://SERVER_ADDRESS:7459/` |
| Health address | `https://localhost:7459/healthz` answers `ok` |
| The helper's own check | `docker exec phlix-camera-upload python -m phlix_upload doctor` |
| The same facts as JSON | `https://localhost:7459/api/v1/health` |
| More about networks, for the owner to read | https://github.com/jrl8085/phlix-camera-upload/blob/main/NETWORKING.md |
| Setup guide | https://phlixapp.com/camera-upload/ |
| Support | https://phlixapp.com/support/ |

How the helper behaves:

- It refuses to start unless `/photos` and `/config` are both real mounts.
- It starts as root, then switches to the user who owns the upload folder. Uploaded files belong to that user.
- It finds Plex Media Server by itself at `host.docker.internal:32400`, over https first. The Compose file makes that name work.
- It needs a moment after it starts. Docker reports `healthy` 30 to 60 seconds later.
- It only receives files. It never deletes a file and never sends one back.
- `curl` needs `-k`, because the certificate is self-signed. That is expected.

How the app behaves:

- Phlix needs version 1.0.21 or later. Camera Upload is under Settings > Camera Upload, where it is marked Beta.
- Phlix looks for the helper at the address of the Plex server, on port 7459. Any other address can be typed into the app.
- Phlix talks HTTPS only.
- Phlix uploads only on the home network: the Wi-Fi network the phone was on when it paired. It never uploads over mobile data, on other Wi-Fi networks, or through a VPN from outside.
- In the app, the owner goes to Settings > Camera Upload and taps Check for the Helper, then Check My Network. If Phlix does not find the helper, Camera Upload stays off and Phlix says Helper not found. When it has found it, the owner taps Connect and then Turn On Camera Upload, and the screen shows a green dot and "Connected to" the helper's name.

Words used in the steps:

- **Install folder**: the folder that holds the Compose file and the helper's data. See Step 1.
- **Library folder**: a folder that the owner's Plex photo library includes.
- **Upload folder**: the new folder named `Camera Uploads` inside the library folder.
- **Host path**: the path of a folder on the server itself.
- **Plex path**: the path of the same folder as Plex sees it. The two differ only when Plex runs in a container.

## Steps

Run every command on the server. If you are on another computer, run the commands on the server over SSH.

On Unraid, Synology, TrueNAS SCALE and Docker Desktop, read [Platform notes](#platform-notes) before Step 1. They change some steps.

### Step 1. Check Docker and choose the install folder

1. Run `docker version --format '{{.Server.Version}}'`.
   - If the command is not found, stop. Tell the owner that Docker is not installed.
   - If the answer is "permission denied", ask the owner whether you may use `sudo` for `docker` commands. Then put `sudo` in front of every `docker` command in this file.
   - If the version is lower than 20.10, stop. Tell the owner that Docker is too old.
2. Run `docker compose version --short`.
   - If the version is 2 or higher, go on.
   - If that command fails, run `docker-compose version --short`. If it answers with version 2 or higher, write `docker-compose` wherever this file says `docker compose`.
   - Otherwise stop. Tell the owner that Docker Compose version 2 is missing.
3. Run `docker ps -a --filter 'name=^/phlix-camera-upload$' --format '{{.Names}}  {{.Status}}'`.
   - If it prints a line, the helper is installed already. Stop and ask the owner whether they want an update. For an update, go to [Update](#update).
4. Run `docker ps --format '{{.Names}}  {{.Ports}}' | grep ':7459->'`.
   - If it prints a line, another container uses port 7459. Stop and ask the owner what to do.
5. Make the install folder. It is `phlix-camera-upload` in the home folder of the user you work as on the server: `mkdir -p ~/phlix-camera-upload`.
   - If the folder already holds a file named `docker-compose.yml`, stop and ask the owner.

### Step 2. Find how Plex runs

1. Run `docker ps --format '{{.Names}}  {{.Image}}' | grep -i plex`.
2. For each container it prints, run `docker top NAME`. The Plex container is the one that shows a process named `Plex Media Server`.
3. If you found the Plex container, Plex runs in a container. Remember its name as PLEX_CONTAINER. Read its folders with this command and no other:

   ```sh
   docker inspect --format '{{range .Mounts}}{{.Type}}  {{.Source}}  =>  {{.Destination}}{{println}}{{end}}' PLEX_CONTAINER
   ```

   Each line shows a host path on the left and the Plex path on the right.
4. If you found no Plex container, run `ps aux | grep "[P]lex Media Server"`. If it prints a line, Plex runs as a normal program on the server. Host paths and Plex paths are then the same.
5. If you found more than one Plex, ask the owner which one holds the photo library.
6. If you found none, ask the owner where Plex runs. If it runs on another machine, stop. Tell the owner that the helper belongs on the machine that runs Plex. Go on here only if that machine cannot run Docker and the owner asks for it: see [Special networks](#special-networks).

### Step 3. Ask the owner for the library folder

Do not look for the library yourself. Ask the owner this question:

> Which folder holds your Plex photo library? To look it up, open Plex in a browser and go to Settings > Manage > Libraries. Choose Edit Library on your photo library, then Add folders. Tell me the folder exactly as Plex shows it.

If Plex runs in a container, show the owner the lines from Step 2 with the question.

The answer is the Plex path of the library folder.

If the owner has no photo library, ask them to make one in Plex first. Do not make it yourself.

### Step 4. Work out the host path

1. If Plex runs as a normal program, the host path is the Plex path.
2. If Plex runs in a container, find the line from Step 2 whose right side is the longest beginning of the Plex path. Replace that beginning with the left side of the same line. The result is the host path.

   Example: the line is `bind  /mnt/media  =>  /data`, and the Plex path is `/data/Photos`. The host path is `/mnt/media/Photos`.
3. If no line fits, the answer from Step 3 does not match the container. Ask the owner again.
4. If the line that fits starts with `volume`, stop and ask the owner. The library is in a Docker volume, not in a normal folder.
5. Run `ls -ld "HOST_PATH_OF_LIBRARY"`. It must be a folder. If it is missing, ask the owner again.

### Step 5. Propose the upload folder and get a yes

1. Add `/Camera Uploads` to both paths. These are the host path and the Plex path of the upload folder.
2. Ask the owner:

   > I will make this folder for the uploads: HOST_PATH_OF_UPLOAD_FOLDER. Plex sees it as PLEX_PATH_OF_UPLOAD_FOLDER. Is that right?

3. Wait for a yes. If the owner names another folder, use it only if it is inside a library folder, and ask again with the new paths.
4. If the folder exists already, do not change it. Tell the owner it exists, and ask whether to use it. With a yes, go to Step 6.
5. Make the folder: `mkdir "HOST_PATH_OF_UPLOAD_FOLDER"`. Do not use `-p`.
6. Run `stat -c '%u:%g %a' "HOST_PATH_OF_LIBRARY"`. It prints the owner, the group and the permissions of the library folder, as numbers.
7. If the owner is not `0`, give the upload folder the same owner, group and permissions, with `chown` and `chmod`. The helper writes files as the owner of the upload folder, so uploads then look like the rest of the library.
8. If the owner is `0`, root owns the library folder. Ask the owner which user should own the uploads.
   - If they name a user, run `id USER` to get the user's numbers. Give the upload folder to that user and group with `chown`. Give it the permissions of the library folder with `chmod`.
   - If they have no wish, give the upload folder the owner, group and permissions of the library folder. The helper then writes files as root, and its log says so. Tell the owner.
9. Run `stat -c '%u:%g %a'` on the upload folder and check the result. If the permissions do not let the owner write, add that with `chmod u+w`.

### Step 6. Write the Compose file

Write this text to `docker-compose.yml` in the install folder. Replace `HOST_PATH_OF_UPLOAD_FOLDER` with the real path. Change nothing else.

```yaml
# Phlix Camera Upload. Setup guide: https://phlixapp.com/camera-upload/
services:
  phlix-camera-upload:
    image: ghcr.io/jrl8085/phlix-camera-upload:1
    container_name: phlix-camera-upload
    restart: unless-stopped
    ports:
      - "7459:7459"
    volumes:
      # The upload folder. It is inside a folder of the Plex photo library.
      - type: bind
        source: HOST_PATH_OF_UPLOAD_FOLDER
        target: /photos
        bind:
          create_host_path: false
      # The helper's own data: paired phones, received files, certificate.
      - ./config:/config
    extra_hosts:
      - "host.docker.internal:host-gateway"
    security_opt:
      - "no-new-privileges:true"
```

Rules for the path:

- Write the path after `source: ` as it is. Spaces inside the path are fine.
- Put the path in single quotes if it contains a colon followed by a space, or a space followed by `#`. Inside single quotes, write a single quote as two single quotes.
- If the path contains a `$`, write it as `$$`.

Add a setting only when this file tells you to. Settings go in one block at the end of the file. Write `environment:` once, in line with `security_opt:`, and put every setting under it. The block looks like this:

```yaml
    environment:
      PLEX_URL: "http://SERVER_ADDRESS:32400"
```

Then run `docker compose config --quiet` in the install folder. It must print nothing.

### Step 7. Start the helper

1. Go to the install folder.
2. Run `docker compose pull`.
3. Run `docker compose up -d`.

If a command fails, find the message in [Troubleshooting](#troubleshooting). Do not try another image, another tag or another port by yourself.

### Step 8. Verify

1. Run `docker compose ps`. The container must be listed as running.
2. Run this command every 10 seconds, for up to 2 minutes, until it prints `running healthy`:

   ```sh
   docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' phlix-camera-upload
   ```

   If it prints `exited` or `restarting`, read the log (number 6 below) and go to [Troubleshooting](#troubleshooting).
3. Run `curl -sk https://localhost:7459/api/v1/hello`. The answer is one line of JSON. It must contain `"service":"phlix-camera-upload"` and `"apiVersion":1`. It holds no secret. If the server has no `curl`, use `wget -qO- --no-check-certificate` in its place.
4. Run the helper's own check. It does not print the pairing code.

   ```sh
   docker exec phlix-camera-upload python -m phlix_upload doctor
   ```

   It must end with `Nothing needs fixing.`, like this:

   ```
   Phlix Camera Upload 1.0.2
   OK       The helper is running on port 7459
   OK       The upload folder /photos can be written to.
   OK       224.7 GB free on the upload disk.
   OK       Plex Media Server found: its owner can pair from Phlix without a code.
   OK       0 paired, 0 files stored (0 bytes).
   NOTE     Pairing code: run `python -m phlix_upload code` the same way to see it.
   Nothing needs fixing.
   ```

   A `NOTE` line is not a problem. A `PROBLEM` line has a `Fix:` line under it. Find the same problem in [Troubleshooting](#troubleshooting) and do what it says there. The rules of this file still apply to every fix.
5. Read the status page:

   ```sh
   curl -sk https://localhost:7459/ | tr '<' '\n' | grep -E '^(th scope="row"|td class)' | sed 's/^[^>]*>//'
   ```

   It prints six names, each with its value on the next line: `Helper`, `Upload folder`, `Free space`, `Plex Media Server`, `Paired devices` and `Files stored`.

   - `Upload folder` must be `Ready`.
   - `Plex Media Server` should start with `Found`. If it starts with `Not found`, wait one minute, run the command, wait five seconds and run it again. The helper looks for Plex again when the page is read. If it is still not found, go to [Troubleshooting](#troubleshooting).
6. Read the log without the pairing code:

   ```sh
   docker logs phlix-camera-upload 2>&1 | grep -v 'Pairing code'
   ```

   Expect lines like these among the others:

   ```
   2026-11-22 08:50:10 INFO    Running as user 1000, group 1000
   2026-11-22 08:50:10 INFO    Upload folder: /photos (ready, 226.2 GB free)
   2026-11-22 08:50:10 INFO    The owner of the Plex server can pair from Phlix without the code.
   2026-11-22 08:50:11 INFO    Found Plex Media Server 1.41.2.9200 at https://host.docker.internal:32400
   ```

   The numbers in `Running as user` must be the owner and group of the upload folder from Step 5.
7. Run `ls -ld "HOST_PATH_OF_UPLOAD_FOLDER/.phlix-upload-tmp"`. The helper made this hidden folder. If it is there, the helper writes to the right folder.
8. If Plex runs in a container, run `docker exec PLEX_CONTAINER ls -ld "PLEX_PATH_OF_UPLOAD_FOLDER/.phlix-upload-tmp"`. If it is there, Plex sees the same folder. This command only reads.

### Step 9. The pairing code

Skip this step unless the owner asks for the pairing code.

If the owner asks, run:

```sh
docker exec phlix-camera-upload python -m phlix_upload code
```

Give the code to the owner. Do not write it into a file.

The owner of the Plex server does not need the code. Other people in the home, with their own Plex account, do.

### Step 10. Check that the phone can reach the helper

Docker usually opens a published port by itself, even when a firewall such as ufw or firewalld is on. So test first, and propose a firewall rule only if the test fails.

1. Find the server's address on the home network. On Linux:

   ```sh
   ip -4 route get 192.0.2.1 | sed -n 's/.* src \([0-9.]*\).*/\1/p'
   ```

   This is SERVER_ADDRESS.
2. If you work from another computer on the same network, run `curl -sk --max-time 5 https://SERVER_ADDRESS:7459/healthz` on that computer. It must print `ok`.
3. If you work on the server itself, you cannot test this. Ask the owner:

   > Please open https://SERVER_ADDRESS:7459 in a browser on your phone or on another computer at home. The browser warns about the certificate. That is expected: choose Advanced or Show Details and continue. Does the page open?

4. If the page does not open, check that the phone or computer is on the same network as the server, not on a guest Wi-Fi.
5. If it still does not open, look for a firewall on the server. Ask before each `sudo`.
   - `sudo ufw status`
   - `sudo firewall-cmd --state`
6. If a firewall is active, tell the owner the exact rule you propose, and wait for a yes. The rule must allow TCP port 7459 from the home network only. Examples, for a home network `192.168.1.0/24`:
   - `sudo ufw allow from 192.168.1.0/24 to any port 7459 proto tcp`
   - `sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port port="7459" protocol="tcp" accept'`, then `sudo firewall-cmd --reload`
7. Never change the router.

### Step 11. Tell the owner what to do next

Give the owner this message. Fill in the four values.

> Phlix Camera Upload is running.
>
> - Status page: https://SERVER_ADDRESS:7459 (your browser warns about the certificate, and that is expected)
> - Uploads go to: HOST_PATH_OF_UPLOAD_FOLDER
> - Plex sees that folder as: PLEX_PATH_OF_UPLOAD_FOLDER
> - The helper's files are in: INSTALL_FOLDER
>
> Two things are left for you to do.
>
> 1. In Plex, switch on Settings > Library > Scan my library automatically. Plex shows new photos only after it scans.
> 2. On your iPhone or iPad, connect to your home Wi-Fi. You need Phlix 1.0.21 or later. Open Phlix and go to Settings > Camera Upload. Tap Check for the Helper, then Check My Network. When Phlix says Helper found, tap Connect, then Turn On Camera Upload. The screen then shows a green dot and "Connected to" the helper's name. Your phone pairs without a code, because your Plex account owns the server.
>
> Other people in your home, with their own Plex account, need the pairing code. Ask me for it, or run: docker exec phlix-camera-upload python -m phlix_upload code
>
> Phlix uploads only on your home Wi-Fi: the network the phone is on when it pairs. The first 100 uploads are free. Phlix Pro uploads the rest. The helper never deletes a file, and removing the helper does not delete your photos.
>
> Camera Upload is a beta, and the app marks it Beta. Keep your own backup of anything you cannot replace. What the beta does and does not do: https://phlixapp.com/camera-upload/#beta
>
> The setup guide, and help when something does not work: https://phlixapp.com/camera-upload/

If the status page says Plex is not found, replace the last sentence of number 2 with: "Type the pairing code when Phlix asks for it."

If Phlix does not find the helper, Camera Upload stays off and Phlix says so. Go to [Troubleshooting](#troubleshooting).

## Platform notes

### Unraid

- Unraid has Docker and no Docker Compose. Skip numbers 2 and 5 of Step 1, and skip Steps 6 and 7.
- There is no install folder. The helper's data goes to `/mnt/user/appdata/phlix-camera-upload`. Use that path for INSTALL_FOLDER in Step 11.
- Plex usually runs in a container. Host paths start with `/mnt/user/`.
- The terminal is root. Still ask before every change.
- In Step 5, give the upload folder the owner `99:100` in every case. The template runs the helper as that user and group.
- In place of Steps 6 and 7:
  1. Ask the owner whether you may add a template file to the flash drive.
  2. Run:

     ```sh
     wget -O /boot/config/plugins/dockerMan/templates-user/my-phlix-camera-upload.xml https://raw.githubusercontent.com/jrl8085/phlix-camera-upload/main/unraid/phlix-camera-upload.xml
     ```

  3. In that file, find the `Config` element with `Name="Photos"`. Make the host path of the upload folder its text. In XML, write `&` as `&amp;` and `<` as `&lt;`.
  4. Ask the owner: "Please open the Docker tab in Unraid. Choose Add Container. Choose phlix-camera-upload in the Template list. Check that Photos is HOST_PATH_OF_UPLOAD_FOLDER. Choose Apply. Tell me when it is done."
  5. Go on with Step 8. Skip `docker compose ps`.
- If the download fails, ask the owner to add the container by hand on the Docker tab: name `phlix-camera-upload`, repository `ghcr.io/jrl8085/phlix-camera-upload:1`, network type `bridge`, extra parameters `--add-host=host.docker.internal:host-gateway --restart=unless-stopped`, port `7459` to `7459` (TCP), path `/photos` to the upload folder, path `/config` to `/mnt/user/appdata/phlix-camera-upload`, and the variables `PUID` = `99`, `PGID` = `100`, `UMASK` = `022`.
- To update: the owner chooses Check for Updates on the Docker tab.

### Synology

- You work over SSH. `docker` needs `sudo`. Ask once.
- Plex usually runs as a package, so host paths and Plex paths are the same. They start with `/volume1/` or another volume.
- The install folder is `phlix-camera-upload` inside the shared folder named `docker`, not in the home folder. Find it with `ls -d /volume*/docker`. If there is none, ask the owner.
- The Compose command may be `docker-compose`. Step 1 tells you how to check.
- In Step 5, do not run `chown` or `chmod`. DSM manages access with its own rules. Make the folder with `mkdir`, or ask the owner to make it in File Station.
- If `Upload folder` is not `Ready` in Step 8, do not change permissions yourself. Ask the owner to give the folder's owner Read/Write permission for the shared folder, in DSM under Control Panel > Shared Folder > Edit > Permissions. Or ask which DSM user should own the uploads, run `id USER`, and add `PUID` and `PGID` with that user's two numbers, in quotes, as Step 6 shows. Then run `docker compose up -d`.
- The firewall is in DSM under Control Panel > Security > Firewall. Ask the owner to allow TCP port 7459 there, if it is on.
- The container shows in Container Manager under Container. It does not show under Project.

### TrueNAS SCALE

- These notes are for version 24.10 or later. On an older version, stop and tell the owner.
- `docker` needs `sudo`. Ask once.
- Plex usually runs as an app, in a container. Host paths start with `/mnt/`.
- Let TrueNAS manage the helper. Write the file in Step 6 into the install folder: it is only the text for the owner to paste. Skip Step 7. In its place:
  1. Ask the owner which folder under `/mnt/` may hold the helper's own data.
  2. In the Compose text from Step 6, replace `./config:/config` with `THAT_FOLDER:/config`. Use that folder for INSTALL_FOLDER in Step 11.
  3. Give the owner the finished text and say: "Please go to Apps > Discover Apps. Open the menu with three dots and choose Install via YAML. Enter the name phlix-camera-upload. Paste this text. Choose Save. Tell me when it is done."
  4. Go on with Step 8. Skip `docker compose ps`.
- If the container has another name, find it with `sudo docker ps --format '{{.Names}}' | grep phlix-camera-upload`. Use that name wherever this file says `phlix-camera-upload`.

### Docker Desktop on Windows or macOS

- Plex runs as a normal program on the computer. Host paths and Plex paths are the same: `C:\Users\NAME\Pictures` or `/Users/NAME/Pictures`.
- In Step 2 on Windows, look for Plex with `Get-Process -Name 'Plex Media Server'`.
- Skip numbers 6 to 9 of Step 5. Docker Desktop writes files as the owner's own user.
- The log may say `Running as root, so uploaded files will belong to root`, and `doctor` then has a NOTE about it. On Docker Desktop both are expected.
- Docker Desktop shows every phone to the helper as one address, so all phones share the helper's limits for one address.
- On Windows, use PowerShell. Write `curl.exe` where this file says `curl`. Make folders with `New-Item -ItemType Directory`. The install folder is `phlix-camera-upload` in the user's home folder, `$HOME\phlix-camera-upload`. There is no `tr`, `grep` or `sed`. In place of number 5 of Step 8, run `curl.exe -sk https://localhost:7459/api/v1/health`. In its JSON, `uploadFolder.writable` must be `true`, and `plex.found` should be `true`.
- Find SERVER_ADDRESS with `ipconfig` on Windows, or `ipconfig getifaddr en0` on macOS.
- On Windows, run `Get-NetConnectionProfile` before Step 7. If `NetworkCategory` is `Public` for the home network, ask the owner to set it to Private. In Windows 11: Settings > Network & internet, then Wi-Fi and the network the PC is connected to, or Ethernet, then Network profile type > Private network. In Windows 10: Settings > Network & Internet, then Wi-Fi or Ethernet and the network, then Network profile > Private. Windows 11 makes a network Public when the PC first connects to it, and Docker Desktop must be allowed on private networks only.
- On Windows, the first start of the helper usually opens a window about Docker Desktop Backend. You cannot see it. Ask the owner to make sure that only the box for Private networks is ticked, and to choose Allow access.
- On Windows, in place of numbers 5 and 6 of Step 10, ask the owner what they chose in that window. After Cancel, a closed window, or an answer for public networks only, Windows keeps blocking Docker Desktop Backend on the home network, and no rule of your own helps: a block rule wins. In that case, and when the owner does not remember, ask the owner to run `Remove-NetFirewallRule -DisplayName "Docker Desktop Backend"` in PowerShell as an administrator. Then ask the owner to quit Docker Desktop, start it again, and answer the window as above.
- On macOS, if the system asks whether Docker may accept connections from the network, ask the owner to allow it.
- Tell the owner that uploads work only while Docker Desktop runs and the computer is awake.

## Troubleshooting

Always start with the helper's own check, when the container runs:

```sh
docker exec phlix-camera-upload python -m phlix_upload doctor
```

Each `PROBLEM` line has a `Fix:` line under it. Then find what you see in this table.

| What you see | Cause | What to do |
| --- | --- | --- |
| `bind source path does not exist` | The upload folder in `docker-compose.yml` is missing or misspelled. | Check the path with `ls -ld`. Correct the `source:` line. Never remove `create_host_path: false`. |
| `invalid IP address in add-host` | Docker is older than 20.10. | Stop. Tell the owner to update Docker. |
| `port is already allocated`, or `address already in use` | Another program uses port 7459. | Run `docker compose down`. Ask the owner what to do. Do not stop the other program. |
| The pull fails with `denied`, `unauthorized`, `manifest unknown` or a timeout | The server cannot reach `ghcr.io`, or the image line is wrong. | Compare the image line with [Facts](#facts). If it is right, stop and tell the owner the exact message. |
| The container exits or keeps restarting. The log says `Nothing is mounted at /photos.` or `Nothing is mounted at /config.` | A volume is missing. | Compare `docker-compose.yml` with Step 6. Run `docker compose up -d` again. |
| The same message, and both folders are in the Compose file | Docker on this server stores containers without a file system of their own, so the helper cannot see the mounts. This is rare. | Run `docker info --format '{{.Driver}}'`. If it prints `vfs`, ask the owner. With a yes, add `ALLOW_UNMOUNTED: "1"` under `environment:`, and run `docker compose up -d`. Then number 7 of Step 8 must pass. If it prints something else, stop and ask the owner. |
| The container exits or keeps restarting. The log says `Phlix Camera Upload cannot start:`, then that the upload folder `is empty, and the helper stored` files there before | The share or disk that holds the upload folder is not mounted, so the helper waits for it. More rarely, the owner emptied the folder. | Run `ls -la "HOST_PATH_OF_UPLOAD_FOLDER"`. If it is empty, check that the share or disk is mounted, and tell the owner. Only if the owner emptied the folder on purpose, and with a yes, run `mkdir "HOST_PATH_OF_UPLOAD_FOLDER/.phlix-upload-tmp"`. Then run `docker compose up -d`. |
| The container exits or keeps restarting. The log says `Phlix Camera Upload cannot start:` and another reason | A setting has a value the helper cannot use. The message names it. | Correct the setting in `docker-compose.yml`. Run `docker compose up -d`. |
| `Upload folder` is not `Ready` | The helper's user may not write to the upload folder. | Compare `Running as user` in the log with `stat -c '%u:%g %a'` of the upload folder. Repeat numbers 6 to 9 of Step 5. Then run `docker compose restart`. |
| The container keeps restarting and the log says `it cannot use its own data folder`, or `Upload folder` is not `Ready`. In both cases `getenforce` prints `Enforcing`. | SELinux keeps the container out of folders that are not labelled for containers. | Ask the owner. With a yes, run `sudo chcon -R -t container_file_t "HOST_PATH_OF_UPLOAD_FOLDER" "INSTALL_FOLDER/config"`. Then run `docker compose restart`. Do not change the Compose file. |
| The log says `Running as root, so uploaded files will belong to root`, and `doctor` has a NOTE that says `The helper runs as root` | Root owns the upload folder. | On Docker Desktop this is expected. Elsewhere, repeat number 8 of Step 5, then run `docker compose restart`. |
| `Plex Media Server` stays `Not found` | The helper cannot reach Plex on port 32400 of the server. | Add `PLEX_URL` as Step 6 shows, with SERVER_ADDRESS from Step 10. Run `docker compose up -d` and repeat Step 8. If it is still not found, take `PLEX_URL` out again, run `docker compose up -d`, and tell the owner that phones pair with the pairing code. |
| The status page says Plex `lets this helper in without signing in`, or `doctor` says so in a `NOTE` | In Plex, the setting List of IP addresses and networks that are allowed without auth includes the helper's address. Plex then cannot confirm who owns the server. | Do not change Plex. Tell the owner that phones pair with the pairing code, and that this Plex setting is the reason. |
| Phlix says "iOS is keeping Phlix off your local network" | The Local Network permission is off for Phlix on the phone. | The owner opens the phone's Settings > Apps > Phlix and switches Local Network on. |
| Phlix does not find the helper, and Camera Upload stays off | The phone cannot reach the helper, or the helper is not at the address of Plex. | Do Step 10. Ask the owner to check two things on the phone: it is on the home Wi-Fi, and no VPN app is on. If that does not help, the owner types `https://SERVER_ADDRESS:7459` into the app. |
| Phlix found the helper at home and uploads nothing elsewhere | Phlix uploads only on the home Wi-Fi: the network the phone was on when it paired. | Nothing is wrong. To add a second network at home, the owner connects to it, opens the Camera Upload screen and chooses This Is My Home Network. |
| Phlix says the Plex account does not own the server, or asks for the pairing code | The phone's Plex account is not the owner's, or Plex could not confirm it. | The owner types the pairing code. Do Step 9 if the owner asks. |
| Phlix says there were too many wrong tries | One address made five wrong tries within a minute. Or all addresses together sent 200 wrong codes within ten minutes: pairing with the code then pauses for everyone, and pairing through Plex still works. | Tell the owner to wait a minute and type the code again. If it goes on, read the log for `Wrong pairing code from`. |
| A phone that was paired says it is no longer paired | The same device paired again, which is normal after a phone was restored. Or the helper lost its `config` folder. | Read the log for `was already paired and has paired again from`. The owner pairs the phone again. If nobody in the home did that, tell the owner to change the pairing code first, with `docker exec phlix-camera-upload python -m phlix_upload new-code` and then `docker restart phlix-camera-upload`. Pairing the phone again after that ends the other pairing. If the helper lost its `config` folder, Phlix says "The server's identity has changed": the owner notes the name in the Folder row of the Camera Upload screen, chooses Disconnect, connects again and types that same folder name, so that files already on the server are not stored twice. |
| Photos reach the upload folder and do not show in Plex | Plex has not scanned, or Plex cannot see the folder. | Tell the owner to switch on Scan my library automatically. Repeat number 8 of Step 8. Do not change Plex yourself. |

### Special networks

Phlix finds the helper by itself only when the helper answers at the address of the Plex server, on port 7459. In the set-ups below it does not, or the helper does not find Plex. Change `docker-compose.yml` only after the owner says yes.

| Set-up | What to do |
| --- | --- |
| The owner wants another port, such as 8443 | Change the line under `ports:` to `- "8443:7459"`. The owner types `https://SERVER_ADDRESS:8443` into the app. |
| A firewall on the server keeps the helper away from Plex, and the owner wants to pair without a code | Use host networking. It works on Linux only. Remove `ports:` and `extra_hosts:` with the line under each. Add `network_mode: host` under `restart: unless-stopped`. Set `PLEX_URL: "http://127.0.0.1:32400"`. |
| The helper has its own address on the home network (macvlan, ipvlan, Unraid Custom: br0) | The owner types `https://ADDRESS_OF_THE_HELPER:7459` into the app. The helper cannot reach a Plex that runs on the same machine, so phones pair with the pairing code. |
| Plex runs on another machine than the helper | The helper must still write into a folder of the Plex library. Set `PLEX_URL` to the address of the Plex machine. The owner types the helper's address into the app. |
| The owner wants the helper behind a reverse proxy | Do not set that up yourself. It is described on the page that [Facts](#facts) names under "More about networks". Give the owner that address. |

## Update

1. Go to the install folder.
2. Run `docker compose pull`.
3. Run `docker compose up -d`.
4. Repeat Step 8.

Phones stay paired. The helper's data in `config` is not touched.

On Unraid, the owner chooses Check for Updates on the Docker tab. On TrueNAS SCALE, the app belongs to TrueNAS: ask the owner to update it there.

## Remove

Remove the helper only when the owner asks.

1. Go to the install folder.
2. Run `docker compose down`.
3. Ask the owner whether to delete the helper's own data. It is the folder `config` in the install folder. Without it, every phone has to pair again after a new install.
4. Ask the owner whether to delete the image. If yes, run `docker image rm ghcr.io/jrl8085/phlix-camera-upload:1`.
5. If you added a firewall rule in Step 10, ask the owner whether to remove it.
6. Never delete the upload folder or a file in it. Removing the helper does not delete photos. The one thing you may delete there, after a yes, is the hidden folder `.phlix-upload-tmp`.

On Unraid, the owner removes the container on the Docker tab. On TrueNAS SCALE, the owner deletes the app under Apps.

Phlix is an independent application and is not affiliated with, endorsed, or sponsored by Plex, Inc.

Plex, the Plex Play logo, and Plex Media Server are trademarks of Plex GmbH and used under a license.
