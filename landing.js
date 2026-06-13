const installCommand = 'curl -fsSL https://meghdadfadaee.github.io/nais/setup.sh | sh';

document.querySelectorAll('[data-copy-command]').forEach((button) => {
    button.addEventListener('click', async () => {
        try {
            await navigator.clipboard.writeText(installCommand);
            const label = button.querySelector('.copy-label');
            label.textContent = 'Copied';
            window.setTimeout(() => {
                label.textContent = 'Copy';
            }, 1800);
        } catch {
            window.prompt('Copy the install command:', installCommand);
        }
    });
});
