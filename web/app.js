/**
 * Server Monitoring Dashboard - Frontend Logic
 * Live polling, reactive gauge updates, and error handling.
 */

const REFRESH_INTERVAL_MS = 3000;
let pollTimer = null;

// DOM Elements
const elHost = document.getElementById('hostname-val');
const elTime = document.getElementById('timestamp-val');
const elLiveDot = document.getElementById('live-indicator');
const elRefreshBtn = document.getElementById('refresh-btn');

const elOsBadge = document.getElementById('os-badge');
const elCpuCores = document.getElementById('cpu-cores');
const elUptime = document.getElementById('uptime-val');
const elLoad1m = document.getElementById('load-1m');
const elLoad5m = document.getElementById('load-5m');
const elLoad15m = document.getElementById('load-15m');
const elCpuStatus = document.getElementById('cpu-status');

const elMemBar = document.getElementById('mem-bar');
const elMemPct = document.getElementById('mem-pct');
const elMemSummary = document.getElementById('mem-summary');
const elMemUsed = document.getElementById('mem-used');
const elMemFree = document.getElementById('mem-free');
const elMemTotal = document.getElementById('mem-total');
const elMemStatusBadge = document.getElementById('mem-status-badge');

const elDiskBar = document.getElementById('disk-bar');
const elDiskPct = document.getElementById('disk-pct');
const elDiskSummary = document.getElementById('disk-summary');
const elDiskUsed = document.getElementById('disk-used');
const elDiskFree = document.getElementById('disk-free');
const elDiskTotal = document.getElementById('disk-total');
const elDiskStatusBadge = document.getElementById('disk-status-badge');

const elServicesContainer = document.getElementById('services-container');

function getBarColorClass(pct) {
  if (pct >= 85) return 'fill-red';
  if (pct >= 70) return 'fill-yellow';
  return 'fill-green';
}

function updateBadge(el, text, type) {
  el.className = `badge badge-${type}`;
  el.textContent = text;
}

async function fetchStats() {
  try {
    const res = await fetch('/api/stats');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    renderDashboard(data);
    elLiveDot.style.backgroundColor = '#10b981';
    elLiveDot.style.boxShadow = '0 0 10px #10b981';
  } catch (err) {
    console.warn('Failed to fetch stats:', err);
    elLiveDot.style.backgroundColor = '#f59e0b';
    elLiveDot.style.boxShadow = '0 0 8px #f59e0b';
    elTime.textContent = 'Disconnected';
  }
}

function renderDashboard(data) {
  const now = new Date();
  elTime.textContent = now.toLocaleTimeString();

  // 1. System & CPU
  if (data.system) {
    elHost.textContent = data.system.hostname || 'server';
    elOsBadge.textContent = data.system.os || 'Linux';
    elCpuCores.textContent = `${data.system.cores || 1} Cores`;
    elUptime.textContent = data.system.uptime || 'N/A';

    const load = data.system.load || [0, 0, 0];
    elLoad1m.textContent = load[0];
    elLoad5m.textContent = load[1];
    elLoad15m.textContent = load[2];

    const cores = data.system.cores || 1;
    if (load[0] > cores) {
      updateBadge(elCpuStatus, 'High Load', 'warning');
    } else {
      updateBadge(elCpuStatus, 'Normal Load', 'success');
    }
  }

  // 2. Memory
  if (data.memory) {
    const m = data.memory;
    const pct = Math.min(100, Math.max(0, m.percent || 0));
    
    elMemBar.style.width = `${pct}%`;
    elMemBar.className = `progress-bar-fill ${getBarColorClass(pct)}`;
    elMemPct.textContent = `${pct}%`;
    elMemSummary.textContent = `${m.used_mb} MB / ${m.total_mb} MB`;
    
    elMemUsed.textContent = `${m.used_mb} MB`;
    elMemFree.textContent = `${m.free_mb} MB`;
    elMemTotal.textContent = `${m.total_mb} MB`;

    if (pct >= 90) {
      updateBadge(elMemStatusBadge, 'Critical', 'danger');
    } else if (pct >= 85) {
      updateBadge(elMemStatusBadge, 'High', 'warning');
    } else {
      updateBadge(elMemStatusBadge, 'Healthy', 'success');
    }
  }

  // 3. Disk
  if (data.disk) {
    const d = data.disk;
    const pct = Math.min(100, Math.max(0, d.percent || 0));

    elDiskBar.style.width = `${pct}%`;
    elDiskBar.className = `progress-bar-fill ${getBarColorClass(pct)}`;
    elDiskPct.textContent = `${pct}%`;
    elDiskSummary.textContent = `${d.used_gb} GB / ${d.total_gb} GB`;

    elDiskUsed.textContent = `${d.used_gb} GB`;
    elDiskFree.textContent = `${d.free_gb} GB`;
    elDiskTotal.textContent = `${d.total_gb} GB`;

    if (pct >= 90) {
      updateBadge(elDiskStatusBadge, 'Critical', 'danger');
    } else if (pct >= 85) {
      updateBadge(elDiskStatusBadge, 'Warning', 'warning');
    } else {
      updateBadge(elDiskStatusBadge, 'Healthy', 'success');
    }
  }

  // 4. Services
  if (Array.isArray(data.services) && data.services.length > 0) {
    elServicesContainer.innerHTML = '';
    data.services.forEach(svc => {
      const item = document.createElement('div');
      item.className = 'service-item';

      const name = document.createElement('span');
      name.className = 'service-name';
      name.textContent = svc.name;

      const badge = document.createElement('span');
      if (svc.running) {
        badge.className = 'badge badge-success';
        badge.textContent = 'Active';
      } else {
        badge.className = 'badge badge-danger';
        badge.textContent = 'Inactive';
      }

      item.appendChild(name);
      item.appendChild(badge);
      elServicesContainer.appendChild(item);
    });
  }

  // 5. Top Processes
  if (data.processes) {
    renderProcesses(data.processes);
  }
}

// Process Table Logic
const elProcCountBadge = document.getElementById('proc-count-badge');
const elSortCpuBtn = document.getElementById('sort-cpu-btn');
const elSortMemBtn = document.getElementById('sort-mem-btn');
const elProcTbody = document.getElementById('proc-tbody');

let currentProcSort = 'cpu';
let latestProcesses = null;

function getResourceLevelClass(pct, warningThresh = 20, dangerThresh = 50) {
  if (pct >= dangerThresh) return 'fill-red';
  if (pct >= warningThresh) return 'fill-yellow';
  return 'fill-green';
}

function getResourceTextClass(pct, warningThresh = 20, dangerThresh = 50) {
  if (pct >= dangerThresh) return 'text-danger';
  if (pct >= warningThresh) return 'text-warning';
  return 'text-normal';
}

function renderProcesses(data) {
  latestProcesses = data;
  if (!data) return;

  if (elProcCountBadge && data.total_count !== undefined) {
    elProcCountBadge.textContent = `${data.total_count} Total Processes`;
  }

  const list = currentProcSort === 'cpu' ? (data.by_cpu || []) : (data.by_mem || []);
  if (!elProcTbody) return;

  if (list.length === 0) {
    elProcTbody.innerHTML = `<tr><td colspan="5" class="table-empty">No active processes found</td></tr>`;
    return;
  }

  const fragment = document.createDocumentFragment();

  list.forEach((proc, index) => {
    const tr = document.createElement('tr');
    tr.className = 'proc-row';

    const cpuPct = typeof proc.cpu === 'number' ? proc.cpu : 0;
    const memPct = typeof proc.mem === 'number' ? proc.mem : 0;

    const cpuBarWidth = Math.min(100, Math.max(2, cpuPct));
    const memBarWidth = Math.min(100, Math.max(2, memPct));

    const cpuBarClass = getResourceLevelClass(cpuPct, 25, 60);
    const cpuTextClass = getResourceTextClass(cpuPct, 25, 60);
    const memBarClass = getResourceLevelClass(memPct, 15, 40);
    const memTextClass = getResourceTextClass(memPct, 15, 40);

    tr.innerHTML = `
      <td class="col-pid">
        <span class="pid-pill">${proc.pid}</span>
      </td>
      <td class="col-comm">
        <div class="comm-cell">
          <span class="comm-name" title="${escapeHtml(proc.command)}">${escapeHtml(proc.command)}</span>
        </div>
      </td>
      <td class="col-user">
        <span class="user-pill">${escapeHtml(proc.user)}</span>
      </td>
      <td class="col-cpu">
        <div class="resource-cell">
          <div class="mini-bar-bg">
            <div class="mini-bar-fill ${cpuBarClass}" style="width: ${cpuBarWidth}%;"></div>
          </div>
          <span class="resource-val ${cpuTextClass}">${cpuPct.toFixed(1)}%</span>
        </div>
      </td>
      <td class="col-mem">
        <div class="resource-cell">
          <div class="mini-bar-bg">
            <div class="mini-bar-fill ${memBarClass}" style="width: ${memBarWidth}%;"></div>
          </div>
          <span class="resource-val ${memTextClass}">${memPct.toFixed(1)}%</span>
        </div>
      </td>
    `;
    fragment.appendChild(tr);
  });

  elProcTbody.innerHTML = '';
  elProcTbody.appendChild(fragment);
}

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

if (elSortCpuBtn && elSortMemBtn) {
  elSortCpuBtn.addEventListener('click', () => {
    if (currentProcSort === 'cpu') return;
    currentProcSort = 'cpu';
    elSortCpuBtn.classList.add('active');
    elSortCpuBtn.setAttribute('aria-selected', 'true');
    elSortMemBtn.classList.remove('active');
    elSortMemBtn.setAttribute('aria-selected', 'false');
    if (latestProcesses) renderProcesses(latestProcesses);
  });

  elSortMemBtn.addEventListener('click', () => {
    if (currentProcSort === 'mem') return;
    currentProcSort = 'mem';
    elSortMemBtn.classList.add('active');
    elSortMemBtn.setAttribute('aria-selected', 'true');
    elSortCpuBtn.classList.remove('active');
    elSortCpuBtn.setAttribute('aria-selected', 'false');
    if (latestProcesses) renderProcesses(latestProcesses);
  });
}

// Initial fetch and polling loop
fetchStats();
pollTimer = setInterval(fetchStats, REFRESH_INTERVAL_MS);

// Manual Refresh Button
elRefreshBtn.addEventListener('click', () => {
  fetchStats();
});
