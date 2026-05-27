'use strict';

'require dom';
'require form';
'require fs';
'require poll';
'require rpc';
'require view';

const DEFAULT_CONFIG_FILE = '/etc/adguardhome/adguardhome.yaml';
const DEFAULT_WORK_DIR = '/var/lib/adguardhome';
const DEFAULT_USER = 'adguardhome';
const DEFAULT_GROUP = DEFAULT_USER;

const DEFAULT_GOGC = '0';
const DEFAULT_GOMAXPROCS = '0';
const DEFAULT_GOMEMLIMIT = '0';

const PATH_REGEX = new RegExp('^/etc(/[^/]+)?/?$');

const POLL_INTERVAL = 5;

const RUNNING_SPAN = `<span style="color: var(--success-color-high); font-weight: bold">${_('Running')}</span>`;
const NOT_RUNNING_SPAN = `<span style="color: var(--error-color-high); font-weight: bold">${_('Not running')}</span>`;

const STORAGE_KEY = 'luci-app-adguardhome';

function getServiceInfo(name) {
	const fn = rpc.declare({
		object: 'service',
		method: 'list',
		params: ['name'],
		expect: { [name]: { instances: { [name]: {} }}},
	});
	return () => fn(name);
}

const getAGHServiceInfo = getServiceInfo('adguardhome');

async function getStatus() {
	try {
		const res = await getAGHServiceInfo();
		const isRunning = res?.instances?.adguardhome?.running;
		return isRunning ?? false;
	} catch (e) {
		console.error(e);
		return false;
	}
}

function getStatusValue(isRunning) {
	return isRunning ? RUNNING_SPAN : NOT_RUNNING_SPAN;
}

async function getVersion() {
	try {
		const res = await fs.exec('/usr/bin/AdGuardHome', ['--version']);
		const version = res.stdout
			? (res.stdout.match(/version\s+(.*)/) || [null, res.stdout.trim()])[1]
			: '';
		return version;
	} catch (e) {
		console.error(e);
		return 'unknown version';
	}
}

function updateStatus(node) {
	const output = node?.querySelector('output');
	return output
		? async () => {
			const isRunning = await getStatus();
			dom.content(output, getStatusValue(isRunning));
		}
		: () => {};
}

function validateConfigFile(_unused, value) {
	if (value == null || value === '') {
		return true;
	}
	if (!value.startsWith('/')) {
		return _('Path must be absolute.');
	}
	if (value.endsWith('/')) {
		return _('Path must not end with a slash.');
	}
	if (PATH_REGEX.test(value)) {
		return _('Configuration file must be stored in its own directory, and not in \'/etc\'.');
	}
	return true;
}

function validateWorkDir(_unused, value) {
	if (value == null || value === '') {
		return true;
	}
	if (!value.startsWith('/')) {
		return _('Path must be absolute.');
	}
	return true;
}

return view.extend({
	load() {
		return Promise.all([
			getStatus(),
			getVersion(),
		]);
	},

	async render([isRunning, version]) {
		const map = new form.Map('adguardhome', _('AdGuard Home'));

		const statusSect = map.section(form.TypedSection, 'status');
		statusSect.anonymous = true;
		statusSect.cfgsections = () => ['status_section'];

		const versionOpt = statusSect.option(form.DummyValue, '_version', _('Version'));
		versionOpt.cfgvalue = () => version;

		const statusOpt = statusSect.option(form.DummyValue, '_status', _('Service Status'));
		statusOpt.rawhtml = true;
		statusOpt.cfgvalue = () => getStatusValue(isRunning);

		const mainSect = map.section(form.TypedSection, 'adguardhome');
		mainSect.anonymous = true;

		mainSect.tab('general', _('General Settings'));
		mainSect.tab(
			'jail',
			_('File System Access'),
			_('Files and directories that AdGuard Home should have read-only or read-write access to.'),
		);
		mainSect.tab(
			'advanced',
			_('Advanced Settings'),
			_('Go environment variables that tune garbage collector and memory management.') +
				' ' + _('Modify at your own risk.'),
		);

		const configFileOpt = mainSect.taboption(
			'general',
			form.Value,
			'config_file',
			_('Configuration file'),
			_('Configuration file must be stored in its own directory, and not in \'/etc\'.') +
				'<br />' + _('Parent directory will be owned by the service user.') +
				'<br />' + _('If empty, defaults to') + ` '${DEFAULT_CONFIG_FILE}'.`,
		);
		configFileOpt.placeholder = DEFAULT_CONFIG_FILE;
		configFileOpt.validate = validateConfigFile;

		const workDirOpt = mainSect.taboption(
			'general',
			form.Value,
			'work_dir',
			_('Working directory'),
			_('Directory where filters, logs, and statistics are stored.') +
				'<br />' + _('Will be owned by the service user.') +
				'<br />' + _('If empty, defaults to') + ` '${DEFAULT_WORK_DIR}'.`,
		);
		workDirOpt.placeholder = DEFAULT_WORK_DIR;
		workDirOpt.validate = validateWorkDir;

		const userOpt = mainSect.taboption(
			'general',
			form.Value,
			'user',
			_('Service user'),
			_('User the service runs under.') + ' ' + _('If empty, defaults to') +
				` '${DEFAULT_USER}'.`,
		);
		userOpt.placeholder = DEFAULT_USER;

		const groupOpt = mainSect.taboption(
			'general',
			form.Value,
			'group',
			_('Service group'),
			_('Group the service runs under.') + ' ' + _('If empty, defaults to') +
				` '${DEFAULT_GROUP}'.`,

		);
		groupOpt.placeholder = DEFAULT_GROUP;

		const verboseOpt = mainSect.taboption(
			'general',
			form.Flag,
			'verbose',
			_('Verbose logging'),
		);
		verboseOpt.default = '0';

		const advSettingsOpt = mainSect.taboption(
			'general',
			form.Flag,
			'advanced_settings',
			_('Advanced Settings'),
		);
		advSettingsOpt.default = '0';
		advSettingsOpt.rmempty = false;
		advSettingsOpt.load = () => sessionStorage.getItem(STORAGE_KEY) || '0';
		advSettingsOpt.remove = () => {};
		advSettingsOpt.write = (_, value) => sessionStorage.setItem(STORAGE_KEY, value);

		mainSect.taboption('jail', form.DynamicList, 'jail_mount', _('Read-only access'));
		mainSect.taboption('jail', form.DynamicList, 'jail_mount_rw', _('Read-write access'));

		const gcOpt = mainSect.taboption(
			'advanced',
			form.Value,
			'gc',
			'GOGC',
			_('Tunes the garbage collector\'s aggressiveness by setting the percentage of heap ' +
				'growth allowed before the next collection cycle triggers.') + '<br />' +
				_('If empty, defaults to') + ' ' + _('unset and 100') + '.',
				'<a href="https://go.dev/doc/gc-guide#GOGC" target="_blank">https://go.dev/doc/gc-guide#GOGC</a>'
		);
		gcOpt.datatype = 'uinteger';
		gcOpt.depends('advanced_settings', '1');
		gcOpt.placeholder = DEFAULT_GOGC;
		gcOpt.retain = true;

		const maxProcsOpt = mainSect.taboption(
			'advanced',
			form.Value,
			'maxprocs',
			'GOMAXPROCS',
			_('The maximum number of operating system threads that can execute user-level Go code' +
				' simultaneously.') + '<br />' +
				_('If empty, defaults to') + ' ' + _('unset and matching the number of CPUs') + '.',
		);
		maxProcsOpt.datatype = 'uinteger';
		maxProcsOpt.depends('advanced_settings', '1');
		maxProcsOpt.placeholder = DEFAULT_GOMAXPROCS;
		maxProcsOpt.retain = true;

		const memLimitOpt = mainSect.taboption(
			'advanced',
			form.Value,
			'memlimit',
			'GOMEMLIMIT',
			_('A soft memory cap for the Go runtime, allowing the garbage collector to run more ' +
				'frequently as usage approaches the limit to prevent Out-of-Memory (OOM) kills.') +
				'<br />' +
				_('If empty, defaults to') + ' ' + _('unset') + '.',
		);
		memLimitOpt.datatype = 'uinteger';
		memLimitOpt.depends('advanced_settings', '1');
		memLimitOpt.placeholder = DEFAULT_GOMEMLIMIT;
		memLimitOpt.retain = true;

		
    // --- Injected Core Update Tab & Fields ---
    mainSect.tab('update', _('Core Update'));

    const coreVerOpt = mainSect.taboption('update', form.ListValue, 'core_version', _('Core Branch'));
    coreVerOpt.value('latest', _('Latest Version'));
    coreVerOpt.value('beta', _('Beta Version'));
    coreVerOpt.default = 'latest';

    const updatePanelOpt = mainSect.taboption('update', form.DummyValue, '_update_panel', _('Core Maintenance'));
    updatePanelOpt.rawhtml = true;
    updatePanelOpt.cfgvalue = () => {
        return `
          <button id="btn_core_update" class="btn cbi-button cbi-button-apply">${_('Update Core Version')}</button>
          <button id="btn_core_force" class="btn cbi-button cbi-button-reset" style="display:none; margin-left:10px;">${_('Force Update')}</button>
          <textarea id="core_update_log" class="cbi-input-textarea" style="width:100%; display:none; font-family:monospace; margin-top:10px; font-size:12px; background:#1e1e1e; color:#d4d4d4; line-height:1.4;" rows="8" readonly></textarea>
        `;
    };

		const rendered = await map.render();

		const statusNode = map.findElement('data-field', statusOpt.cbid('status_section'));
		poll.add(updateStatus(statusNode), POLL_INTERVAL);

// --- Injected Core Update DOM Logic ---
const btnUpdate = document.getElementById('btn_core_update');
const btnForce = document.getElementById('btn_core_force');
const logTextarea = document.getElementById('core_update_log');
let intervalId = null;

const startLogPolling = () => {
    if (intervalId) clearInterval(intervalId);
    intervalId = setInterval(() => {
        // 异步倾倒实时运行日志
        fs.read('/tmp/AdGuardHome_update.log').then((txt) => {
            if (txt && logTextarea) {
                logTextarea.value = txt;
                logTextarea.scrollTop = logTextarea.scrollHeight; // 始终锚定底部滚动
            }
        }).catch(() => {});

        // 根据标志锁文件的存亡判定任务状态
        fs.stat('/var/run/update_core').then(() => {
            // 锁文件存在 -> 脚本还在运行
        }).catch(() => {
            // 锁文件失联 -> 运行结束，释放控制器
            clearInterval(intervalId);
            if (btnUpdate) btnUpdate.disabled = false;
            if (btnForce) btnForce.disabled = false;

            fs.stat('/var/run/update_core_error').then(() => {
                if (btnUpdate) btnUpdate.textContent = _('Failed');
            }).catch(() => {
                if (btnUpdate) btnUpdate.textContent = _('Updated');
                setTimeout(() => { location.reload(); }, 1000); // 丝滑重载
            });
        });
    }, 1500);
};

if (btnUpdate && btnForce && logTextarea) {
    // 绑定普通更新事件
    btnUpdate.addEventListener('click', (ev) => {
        ev.preventDefault();
        btnUpdate.disabled = true;
        btnUpdate.textContent = _('Checking...');
        btnForce.style.display = 'inline-block';
        logTextarea.style.display = 'block';

        fs.exec('/bin/sh', ['-c', '/usr/share/AdGuardHome/update_core.sh >/tmp/AdGuardHome_update.log 2>&1 &']).then(() => {
            startLogPolling();
        });
    });

    // 绑定强制更新事件
    btnForce.addEventListener('click', (ev) => {
        ev.preventDefault();
        btnUpdate.disabled = true;
        btnForce.disabled = true;
        btnUpdate.textContent = _('Checking...');
        logTextarea.style.display = 'block';

        fs.exec('/bin/sh', ['-c', '/usr/share/AdGuardHome/update_core.sh force >/tmp/AdGuardHome_update.log 2>&1 &']).then(() => {
            startLogPolling();
        });
    });
}

// 守护安全逻辑：若用户在更新中途误刷新了网页，检测到状态锁仍能复活轮询
fs.stat('/var/run/update_core').then(() => {
    if (btnUpdate && btnForce && logTextarea) {
        btnUpdate.disabled = true;
        btnUpdate.textContent = _('Checking...');
        btnForce.style.display = 'inline-block';
        logTextarea.style.display = 'block';
        startLogPolling();
    }
}).catch(() => {});


		return rendered;
	},
});
