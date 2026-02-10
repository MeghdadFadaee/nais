
/**
 * Check if a URL points to a file by extension
 */
function isFileLink(url) {
    const fileExtensions = [
        'pdf','zip','rar','7z',
        'mp3','mp4','mkv','avi',
        'jpg','jpeg','png','gif','webp',
        'doc','docx','xls','xlsx','ppt','pptx',
        'csv','txt','json'
    ];

    const cleanUrl = url.split('?')[0].toLowerCase();
    return fileExtensions.some(ext => cleanUrl.endsWith('.' + ext));
}

/**
 * Get all file links from the page
 */
function getFileLinks() {
    const links = document.querySelectorAll('a');
    const result = [];

    links.forEach(a => {
        if (!a.href) return;
        if (!isFileLink(a.href)) return;

        result.push({
            text: a.innerText.trim(),
            href: a.href
        });
    });

    return result;
}

/**
 * Converts a string to kebab-case.
 */
function toKebabCase(str) {
    return str
        .toLowerCase()
        .trim()
        .replace(/['’]/g, '')
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '');
}

/**
 * Extracts the last directory or file name from the current page URL
 */
function getDirectoryName() {
    const url = new URL(window.location.href);
    const lastPart = url.pathname
        .split('/')
        .filter(Boolean)
        .pop() || 'file-links';

    return decodeURIComponent(lastPart);
}

/**
 * Download file links as Playlist
 */
function downloadPlaylist() {
    const files = getFileLinks();
    let content = 'DAUMPLAYLIST\n';

    files.forEach((item, index) => {
        const text = item.text.replace(/"/g, '""');
        const href = item.href.replace(/"/g, '""');
        content += `${index+1}*file*${href}\n`;
    });

    const blob = new Blob([content], { type: 'application/octet-stream;charset=utf-8;' });
    const url = URL.createObjectURL(blob);

    const a = document.createElement('a');
    a.href = url;
    a.download = toKebabCase(getDirectoryName()) + '.dpl';
    a.style.display = 'none';

    document.body.appendChild(a);
    a.click();

    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}

/**
 * Copy file links (one per line)
 */
function copyAllLinks() {
    const files = getFileLinks();
    const textToCopy = files.map(f => f.href).join('\n');

    // Modern browsers
    if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(textToCopy);
        return;
    }

    // Fallback (older browsers, some mobiles)
    const textarea = document.createElement('textarea');
    textarea.value = textToCopy;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';

    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();

    document.execCommand('copy');
    document.body.removeChild(textarea);
}

(function () {
    const header = document.querySelector('h1');
    if (!header) return;

    // Wrapper for buttons
    const actions = document.createElement('div');
    actions.className = 'autoindex-actions';

    // Playlist button
    const plb = document.createElement('button');
    plb.className = 'ai-btn';
    plb.textContent = 'Download Playlist';
    plb.onclick = downloadPlaylist;

    // Copy Links button
    const clb = document.createElement('button');
    clb.className = 'ai-btn';
    clb.textContent = 'Copy Links';
    clb.onclick = copyAllLinks;

    actions.appendChild(clb);
    actions.appendChild(plb);
    header.appendChild(actions);
})();
