const fs = require("fs/promises");
const path = require("path");

const [kendoVersion, themesVersion, ...options] = process.argv.slice(2);
const versionPattern = /^\d+\.\d+\.\d+$/;
const hashPattern = /^[A-Za-z0-9+/]{43}=$/;
const tagPattern = /<(?:script|link)\b[^>]*>/gi;
const assetPattern = /https:\/\/cdn\.jsdelivr\.net\/npm\/(\@{1,2}progress\/(?:kendo-ui|kendo-theme-[\w-]+))@(\d+\.\d+\.\d+)\/([^"'?#\s>]+)/i;
const fileExtensions = new Set([".html", ".htm", ".cshtml"]);
const ignoredDirectories = new Set([".git", "node_modules", "bin", "obj", "packages"]);
const dryRun = options.includes("--dry-run");
const rootOption = options.find((option) => option.startsWith("--root="));
const rootDirectory = path.resolve(rootOption ? rootOption.slice("--root=".length) : process.cwd());

if (!versionPattern.test(kendoVersion || "") || !versionPattern.test(themesVersion || "")) {
    throw new Error("Usage: node update-kendo-assets.js <kendo-version> <themes-version> [--dry-run] [--root=directory]");
}

async function findSourceFiles(directory) {
    const entries = await fs.readdir(directory, { withFileTypes: true });
    const nestedFiles = await Promise.all(entries.map(async (entry) => {
        const entryPath = path.join(directory, entry.name);

        if (entry.isDirectory()) {
            return ignoredDirectories.has(entry.name) ? [] : findSourceFiles(entryPath);
        }

        return fileExtensions.has(path.extname(entry.name).toLowerCase()) ? [entryPath] : [];
    }));

    return nestedFiles.flat();
}

async function readIntegrity(packageName, version, filePath) {
    const metadataUrl = `https://data.jsdelivr.com/v1/package/npm/${packageName}@${version}/flat`;
    let metadata;
    try {
        const response = await fetch(metadataUrl, { headers: { accept: "application/json" } });

        if (!response.ok) {
            console.warn(`jsDelivr integrity metadata is unavailable for ${packageName}@${version}; the supplied version will be used and the integrity attribute will not be applied.`);
            return null;
        }

        metadata = await response.json();
    } catch (error) {
        console.warn(`jsDelivr integrity metadata is unavailable for ${packageName}@${version}; the supplied version will be used and the integrity attribute will not be applied.`);
        return null;
    }

    const file = metadata.files?.find((entry) => entry.name.replace(/^\//, "") === filePath);

    if (!file || typeof file.hash !== "string" || !hashPattern.test(file.hash)) {
        console.warn(`jsDelivr integrity metadata is unavailable for ${packageName}@${version}/${filePath}; the supplied version will be used and the integrity attribute will not be applied.`);
        return null;
    }

    return `sha256-${file.hash}`;
}

function updateTag(tag, asset, integrity) {
    const updatedUrl = asset.url.replace(`@${asset.currentVersion}/`, `@${asset.targetVersion}/`);
    let updatedTag = tag.replace(asset.url, updatedUrl);
    const integrityPattern = /(\sintegrity\s*=\s*)(["'])[^"']*\2/i;
    const crossoriginPattern = /(\scrossorigin\s*=\s*)(["'])[^"']*\2/i;
    updatedTag = updatedTag.replace(integrityPattern, "").replace(crossoriginPattern, "");

    if (integrity) {
        updatedTag = updatedTag.replace(/\s*\/?>$/, (closing) => ` integrity="${integrity}"${closing}`);
        updatedTag = updatedTag.replace(/\s*\/?>$/, (closing) => ` crossorigin="anonymous"${closing}`);
    }

    return updatedTag;
}

async function main() {
    const files = await findSourceFiles(rootDirectory);
    const updatesByFile = new Map();
    const integrityRequests = new Map();
    let assetCount = 0;

    for (const filePath of files) {
        const content = await fs.readFile(filePath, "utf8");
        const tagUpdates = [];

        for (const match of content.matchAll(tagPattern)) {
            const tag = match[0];
            const urlMatch = tag.match(assetPattern);

            if (!urlMatch) {
                continue;
            }

            const packageName = urlMatch[1].replace(/^@@/, "@");
            const currentVersion = urlMatch[2];
            const fileName = urlMatch[3];
            const targetVersion = packageName === "@progress/kendo-ui" ? kendoVersion : themesVersion;
            const key = `${packageName}@${targetVersion}/${fileName}`;
            const url = urlMatch[0];

            if (!integrityRequests.has(key)) {
                integrityRequests.set(key, readIntegrity(packageName, targetVersion, fileName));
            }

            tagUpdates.push({ tag, asset: { url, currentVersion, targetVersion, fileName, packageName, key } });
        }

        if (tagUpdates.length) {
            updatesByFile.set(filePath, { content, tagUpdates });
            assetCount += tagUpdates.length;
        }
    }

    if (assetCount === 0) {
        throw new Error(`No pinned jsDelivr Kendo UI or theme asset tags were found under ${rootDirectory}`);
    }

    const integrityValues = new Map(await Promise.all(
        [...integrityRequests].map(async ([key, request]) => [key, await request])
    ));

    for (const [filePath, file] of updatesByFile) {
        let updatedContent = file.content;
        for (const { tag, asset } of file.tagUpdates) {
            updatedContent = updatedContent.replace(tag, updateTag(tag, asset, integrityValues.get(asset.key)));
        }

        if (updatedContent !== file.content) {
            if (dryRun) {
                console.log(`Would update ${path.relative(rootDirectory, filePath)}`);
            } else {
                await fs.writeFile(filePath, updatedContent);
            }
        }
    }

    console.log(`${dryRun ? "Validated" : "Updated"} ${assetCount} Kendo asset tags in ${updatesByFile.size} files.`);
}

main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
});