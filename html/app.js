async function loadStatus() {
    const res = await fetch("api/status.json");
    const data = await res.json();
    document.getElementById("status").innerHTML =
        `<h2>Status</h2>
         <p>Last Run: ${data.timestamp}</p>
         <p>Log File: ${data.logfile}</p>`;
}

async function loadRepos() {
    const res = await fetch("api/repos.json");
    const data = await res.json();
    let html = "<h2>Repositories</h2><ul>";
    data.repos.forEach(r => html += `<li>${r}</li>`);
    html += "</ul>";
    document.getElementById("repos").innerHTML = html;
}

loadStatus();
loadRepos();
