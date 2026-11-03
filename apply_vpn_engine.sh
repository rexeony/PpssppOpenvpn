#!/usr/bin/env bash
# Tahap 1: menggabungkan mesin OpenVPN (ics-openvpn) sebagai modul library ke build PPSSPP.
# Pakai: bash apply_vpn_engine.sh <folder ppsspp> <folder ics-openvpn (sudah clone + submodule)>
set -euo pipefail

PPSSPP="$(cd "${1:?Pakai: apply_vpn_engine.sh <ppsspp> <ics-openvpn>}" && pwd)"
ICS="$(cd "${2:?Pakai: apply_vpn_engine.sh <ppsspp> <ics-openvpn>}" && pwd)"
MOD="$ICS/main"

[ -f "$MOD/build.gradle.kts" ] || { echo "ERROR: $MOD/build.gradle.kts tidak ada"; exit 1; }
[ -f "$PPSSPP/android/build.gradle.kts" ] || { echo "ERROR: source PPSSPP tidak ditemukan"; exit 1; }

# Pastikan submodule native sudah terunduh (kalau kosong, build C++ pasti gagal).
if [ -z "${SKIP_SUBMODULE_CHECK:-}" ]; then
  for d in openvpn openssl openvpn3/client asio lz4 fmt; do
    if [ -z "$(ls -A "$MOD/src/main/cpp/$d" 2>/dev/null)" ]; then
      echo "ERROR: submodule kosong: main/src/main/cpp/$d (clone harus pakai --recurse-submodules)"; exit 1
    fi
  done
fi

python3 - "$PPSSPP" "$ICS" <<'PY'
import os, re, sys

ppsspp, ics = sys.argv[1], sys.argv[2]
mod = os.path.join(ics, "main")

def read(p):
    with open(p, encoding="utf-8", newline="") as f:
        return f.read()

def write(p, s):
    with open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)

# ---------- nilai toolchain dari PPSSPP ----------
app_gradle_path = os.path.join(ppsspp, "android", "build.gradle.kts")
app_gradle = read(app_gradle_path)
m = re.search(r'compileSdk\s*=\s*(\d+)', app_gradle)
compile_sdk = m.group(1) if m else "36"
m = re.search(r'ndkVersion\s*=\s*"([^"]+)"', app_gradle)
ndk_version = m.group(1) if m else "29.0.14206865"
print(f"compileSdk={compile_sdk} ndkVersion={ndk_version}")

# ---------- 1. build.gradle.kts modul mesin VPN (library, tanpa UI) ----------
orig_path = os.path.join(mod, "build.gradle.kts")
orig = read(orig_path).replace("\r\n", "\n")
if "OPENVPN-LIBRARY" not in orig:
    open(orig_path + ".orig", "w").write(orig)
else:
    orig = read(orig_path + ".orig")

a = orig.index("var swigcmd")
b = orig.index("\ndependencies {")
swig_block = orig[a:b]

new_build = f'''// OPENVPN-LIBRARY: dibuat otomatis oleh apply_vpn_engine.sh (versi library tanpa UI dari ics-openvpn)
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskProvider

plugins {{
    id("com.android.library")
}}

android {{
    namespace = "de.blinkt.openvpn"
    compileSdk = {compile_sdk}
    ndkVersion = "{ndk_version}"

    buildFeatures {{
        aidl = true
        buildConfig = true
    }}

    buildTypes {{
        // Samakan dengan build type "optimized" milik PPSSPP supaya Gradle menemukan varian library.
        create("optimized") {{
            initWith(getByName("release"))
        }}
    }}

    defaultConfig {{
        minSdk = 23
        buildConfigField("boolean", "openvpn3", "true")
        // Library tanpa product flavor tidak punya BuildConfig.FLAVOR; kode ics-openvpn memakainya.
        buildConfigField("String", "FLAVOR", "\\"skeleton\\"")
        if (project.hasProperty("OPENVPN_ARM64_ONLY")) {{
            ndk {{
                abiFilters.add("arm64-v8a")
            }}
        }}
    }}

    externalNativeBuild {{
        cmake {{
            path = File("${{projectDir}}/src/main/cpp/CMakeLists.txt")
        }}
    }}

    sourceSets {{
        getByName("main") {{
            assets.directories.add("build/ovpnassets")
            // flavor "skeleton" bawaan ics-openvpn (stub tanpa UI) dijadikan bagian dari main
            java.directories.add("src/skeleton/java")
            res.directories.add("src/skeleton/res")
        }}
    }}

    compileOptions {{
        targetCompatibility = JavaVersion.VERSION_17
        sourceCompatibility = JavaVersion.VERSION_17
    }}

    lint {{
        abortOnError = false
    }}
}}

{swig_block}

dependencies {{
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("androidx.core:core:1.16.0")
}}
'''
write(orig_path, new_build)
print("OK  build.gradle.kts modul mesin VPN ditulis")

# ---------- 2. AndroidManifest modul ----------
man_path = os.path.join(mod, "src", "main", "AndroidManifest.xml")
man = read(man_path)
if "OPENVPN-PATCHED" not in man:
    open(man_path + ".orig", "w", encoding="utf-8", newline="").write(man)
    skel = read(os.path.join(mod, "src", "skeleton", "AndroidManifest.xml"))
    sm = re.search(r'<application[^>]*>(.*)</application>', skel, re.S)
    skel_inner = sm.group(1) if sm else ""

    # <application> disederhanakan: ikon/tema/label aplikasi PPSSPP yang dipakai, bukan milik ics-openvpn.
    man, n1 = re.subn(r'<application\b[^>]*>',
                      '<application android:name=".core.ICSOpenVPNApplication" tools:ignore="UnusedAttribute">',
                      man, count=1, flags=re.S)
    # permission yang tidak kita butuhkan (daftar semua aplikasi, hanya untuk UI ics-openvpn)
    man, n2 = re.subn(r'<uses-permission\s+android:name="android\.permission\.QUERY_ALL_PACKAGES"[^>]*/>',
                      '', man, flags=re.S)
    # komponen stub (NotImplemented, LogWindow, Req) dari flavor skeleton
    man, n3 = re.subn(r'</application>', skel_inner + '\n    </application>', man, count=1)
    man += "\n<!-- OPENVPN-PATCHED -->\n"
    assert n1 == 1 and n3 == 1, f"manifest tidak cocok (application={n1}, end={n3})"
    write(man_path, man)
    print(f"OK  manifest dipatch (permission QUERY_ALL_PACKAGES dihapus: {n2})")
else:
    print("OK  manifest sudah dipatch")

# ---------- 3. PPSSPP: settings / root build / app build ----------
rel = os.path.relpath(mod, ppsspp).replace(os.sep, "/")

st_path = os.path.join(ppsspp, "settings.gradle.kts")
st = read(st_path)
if ":openvpn-engine" not in st:
    st += f'\ninclude(":openvpn-engine")\nproject(":openvpn-engine").projectDir = file("{rel}")\n'
    write(st_path, st)
print("OK  settings.gradle.kts")

rb_path = os.path.join(ppsspp, "build.gradle.kts")
rb = read(rb_path)
if 'com.android.library' not in rb:
    mm = re.search(r'id\("com\.android\.application"\)\s+version\s+"([^"]+)"\s+apply\s+false', rb)
    assert mm, "plugin com.android.application tidak ditemukan di build.gradle.kts root"
    line = mm.group(0)
    rb = rb.replace(line, line + f'\n\tid("com.android.library") version "{mm.group(1)}" apply false', 1)
    write(rb_path, rb)
print("OK  build.gradle.kts root (plugin library)")

if 'project(":openvpn-engine")' not in app_gradle:
    anchor = 'implementation("com.google.protobuf:protobuf-javalite:4.33.5")'
    assert anchor in app_gradle, "anchor dependensi PPSSPP tidak ditemukan"
    app_gradle = app_gradle.replace(anchor, anchor + '\n\timplementation(project(":openvpn-engine"))', 1)
    assert 'minSdk = 21' in app_gradle, "minSdk = 21 tidak ditemukan"
    app_gradle = app_gradle.replace('minSdk = 21', 'minSdk = 23', 1)   # mesin VPN membutuhkan minSdk 23
    write(app_gradle_path, app_gradle)
print("OK  android/build.gradle.kts (dependensi + minSdk 23)")

# Build type "optimized" milik PPSSPP tidak ada di library VPN -> pakai varian "release" library.
app_gradle = read(app_gradle_path)
if 'matchingFallbacks' not in app_gradle:
    app_gradle, n = re.subn(r'(create\("optimized"\)\s*\{\s*isMinifyEnabled\s*=\s*false)',
                            r'\1\n\t\t\tmatchingFallbacks.add("release")', app_gradle, count=1)
    assert n == 1, "build type optimized tidak ditemukan di android/build.gradle.kts"
    write(app_gradle_path, app_gradle)
print("OK  build type optimized -> fallback release")
PY

echo "OK: mesin VPN (ics-openvpn) digabungkan ke PPSSPP"
