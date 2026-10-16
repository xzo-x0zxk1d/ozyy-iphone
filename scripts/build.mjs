import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { existsSync, mkdirSync, copyFileSync, rmSync, readFileSync, writeFileSync } from "node:fs";
import { resolve, join } from "node:path";
import { createHash } from "node:crypto";
const root = fileURLToPath(new URL("../", import.meta.url));
if (process.platform !== "darwin") {
  console.error("iPhone compilation runs on macOS/Xcode. Use the prepared cloud workflow from Windows; this local command cannot compile an IPA on Windows.");
  process.exit(2);
}
const checked = spawnSync("xcodebuild",["-version"],{encoding:"utf8"});
if(checked.status!==0) { console.error("BLOCKED: Xcode is unavailable."); process.exit(2); }
if(process.argv.includes("--check")){console.log(checked.stdout.trim());process.exit(0);}
const output = join(root,"build");
mkdirSync(output,{recursive:true});
const args=["-project",join(root,"Ozyy.xcodeproj"),"-scheme","Ozyy","-configuration","Release"];
if(process.argv.includes("--simulator")) {
  const r=spawnSync("xcodebuild",[...args,"-sdk","iphonesimulator","-destination","generic/platform=iOS Simulator","-derivedDataPath",join(output,"simulator"),"CODE_SIGNING_ALLOWED=NO","build"],{stdio:"inherit"});process.exit(r.status??1);
}
if(process.argv.includes("--unsigned")) {
  const archive = join(output, "Ozyy-unsigned.xcarchive");
  const built = spawnSync("xcodebuild", [...args, "-destination", "generic/platform=iOS", "-archivePath", archive,
    "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "DEVELOPMENT_TEAM=", "archive"], {stdio:"inherit"});
  if (built.status !== 0) process.exit(built.status ?? 1);
  const app = join(archive, "Products", "Applications", "Ozyy.app");
  if (!existsSync(join(app, "Ozyy"))) throw new Error("The compiled iPhone executable is missing.");
  const release = join(output, "sideload");
  mkdirSync(release, {recursive: true});
  const payload = join(release, "Payload");
  // Only remove this build's own staging directory, never a caller-supplied path.
  rmSync(payload, {recursive: true, force: true});
  mkdirSync(payload);
  const copied = spawnSync("ditto", [app, join(payload, "Ozyy.app")], {stdio:"inherit"});
  if (copied.status !== 0) process.exit(copied.status ?? 1);
  const ipa = join(release, "Ozyy-unsigned.ipa");
  const zipped = spawnSync("ditto", ["-c", "-k", "--keepParent", "--norsrc", payload, ipa], {stdio:"inherit"});
  if (zipped.status !== 0) process.exit(zipped.status ?? 1);
  rmSync(payload, {recursive:true, force:true});
  const digest = createHash("sha256").update(readFileSync(ipa)).digest("hex");
  writeFileSync(join(release, "SHA256SUMS"), `${digest}  Ozyy-unsigned.ipa\n`);
  copyFileSync(join(root, "SIDELOAD.md"), join(release, "READ-ME-FIRST.md"));
  writeFileSync(join(release, "build-info.json"), JSON.stringify({
    bundleIdentifier: "xyz.ozyy.mobile", signed: false, requiresPersonalSigning: true,
    websiteInstallerReady: false, sha256: digest, minimumIOS: "17.0",
    sourceCommit: process.env.GITHUB_SHA ?? null,
  }, null, 2));
  console.log(`Compiled unsigned iPhone app: ${ipa}. It must be personally signed before installation.`);
  process.exit(0);
}
// Use an already-authorized team and caller-supplied export options; never create accounts,
// purchase signing, or select an enterprise distribution entitlement automatically.
const team=process.env.OZYY_APPLE_TEAM_ID;
const exportOptions=process.env.OZYY_IOS_EXPORT_OPTIONS;
if(!team||!/^[A-Z0-9]{10}$/.test(team)||!exportOptions||!existsSync(resolve(exportOptions))) {
  console.error("BLOCKED: Set an existing OZYY_APPLE_TEAM_ID and OZYY_IOS_EXPORT_OPTIONS. No new account or paid service is provisioned by this script.");process.exit(2);
}
const archive=join(output,"Ozyy.xcarchive");
const built=spawnSync("xcodebuild",[...args,"-destination","generic/platform=iOS","-archivePath",archive,`DEVELOPMENT_TEAM=${team}`,"archive"],{stdio:"inherit"});
if(built.status!==0)process.exit(built.status??1);
const exported=spawnSync("xcodebuild",["-exportArchive","-archivePath",archive,"-exportPath",join(output,"export"),"-exportOptionsPlist",resolve(exportOptions)],{stdio:"inherit"});
process.exit(exported.status??1);
