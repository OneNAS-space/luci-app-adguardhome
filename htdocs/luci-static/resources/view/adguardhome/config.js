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
const DEFAULT_GOMAXPROCS = '0'; // 修正拼写
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
	if (value == null || value === '') return true;
	if (!value.startsWith('/')) return _('Path must be absolute.');
	if (value.endsWith('/')) return _('Path must not end with a slash.');
	if (PATH_REGEX.test(value)) return _('Configuration file must be stored in its own directory, and not in \'/etc\'.');
	return true;
}

function validateWorkDir(_unused, value) {
	if (value == null || value === '') return true;
	if (!value.startsWith('/')) return _('Path must be absolute.');
	return true;
}

return view.extend({
	load() {
		return Promise.all([getStatus(), getVersion()]);
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
		mainSect.tab('jail', _('File System Access'), _('Files and directories that AdGuard Home should have read-only or read-write access to.'));
		mainSect.tab('advanced', _('Advanced Settings'), _('Go environment variables that tune garbage collector and memory management.') + ' ' + _('Modify at your own risk.'));

		const configFileOpt = mainSect.taboption('general', form.Value, 'config_file', _('Configuration file'));
		configFileOpt.placeholder = DEFAULT_CONFIG_FILE;
		configFileOpt.validate = validateConfigFile;
		
		const workDirOpt = mainSect.taboption('general', form.Value, 'work_dir', _('Working directory'));
		workDirOpt.placeholder = DEFAULT_WORK_DIR;
		workDirOpt.validate = validateWorkDir;
		
		const userOpt = mainSect.taboption('general', form.Value, 'user', _('Service user'));
		userOpt.placeholder = DEFAULT_USER;

		const groupOpt = mainSect.taboption('general', form.Value, 'group', _('Service group'));
		groupOpt.placeholder = DEFAULT_GROUP;

		const verboseOpt = mainSect.taboption('general', form.Flag, 'verbose', _('Verbose logging'));
		verboseOpt.default = '0';

		const advSettingsOpt = mainSect.taboption('general', form.Flag, 'advanced_settings', _('Advanced Settings'));
		advSettingsOpt.default = '0';
		advSettingsOpt.rmempty = false;
		advSettingsOpt.load = () => sessionStorage.getItem(STORAGE_KEY) || '0';
		advSettingsOpt.remove = () => {};
		advSettingsOpt.write = (_, value) => sessionStorage.setItem(STORAGE_KEY, value);

		mainSect.taboption('jail', form.DynamicList, 'jail_mount', _('Read-only access'));
		mainSect.taboption('jail', form.DynamicList, 'jail_mount_rw', _('Read-write access'));

		const gcOpt = mainSect.taboption('advanced', form.Value, 'gc', 'GOGC');
		gcOpt.datatype = 'uinteger';
		gcOpt.depends('advanced_settings', '1');
		gcOpt.placeholder = DEFAULT_GOGC;

		const maxProcsOpt = mainSect.taboption('advanced', form.Value, 'maxprocs', 'GOMAXPROCS');
		maxProcsOpt.datatype = 'uinteger';
		maxProcsOpt.depends('advanced_settings', '1');
		maxProcsOpt.placeholder = DEFAULT_GOMAXPROCS;

		const memLimitOpt = mainSect.taboption('advanced', form.Value, 'memlimit', 'GOMEMLIMIT');
		memLimitOpt.datatype = 'uinteger';
		memLimitOpt.depends('advanced_settings', '1');
		memLimitOpt.placeholder = DEFAULT_GOMEMLIMIT;

		// --- Core Update Tab ---
		mainSect.tab('update', _('Core Update'));

		const coreVerOpt = mainSect.taboption('update', form.ListValue, 'core_version', _('Core Branch'));
		coreVerOpt.value('latest', _('Latest Version'));
		coreVerOpt.value('beta', _('Beta Version'));
		coreVerOpt.default = 'latest';

		const updateUrlOpt = mainSect.taboption('update', form.Value, 'update_url', _('Core-bin Update URL'));
		updateUrlOpt.default = 'https://github.com/AdguardTeam/AdGuardHome/releases/download/${Cloud_Version}/AdGuardHome_linux_${Arch}.tar.gz';
		updateUrlOpt.placeholder = 'https://github.com/AdguardTeam/AdGuardHome/releases/download/${Cloud_Version}/AdGuardHome_linux_${Arch}.tar.gz';
		updateUrlOpt.rmempty = false;

		const updatePanelOpt = mainSect.taboption('update', form.DummyValue, '_update_panel', _('Core Maintenance'));
		updatePanelOpt.rawhtml = true;
		updatePanelOpt.cfgvalue = () => `
			<button id="btn_core_update" class="btn cbi-button cbi-button-apply">${_('Update Core Version')}</button>
			<button id="btn_core_force" class="btn cbi-button cbi-button-reset" style="display:none; margin-left:10px;">${_('Force Update')}</button>
			<textarea id="core_update_log" class="cbi-input-textarea" style="width:100%; display:none; font-family:monospace; margin-top:10px; font-size:12px; background:#1e1e1e; color:#d4d4d4; line-height:1.4;" rows="8" readonly></textarea>
		`;

		const rendered = await map.render();
		const statusNode = map.findElement('data-field', statusOpt.cbid('status_section'));
		poll.add(updateStatus(statusNode), POLL_INTERVAL);

		// --- Core Update DOM Logic ---
		const btnUpdate = rendered.querySelector('#btn_core_update');
		const btnForce = rendered.querySelector('#btn_core_force');
		const logTextarea = rendered.querySelector('#core_update_log');
		let intervalId = null;

		const startLogPolling = () => {
			if (intervalId) clearInterval(intervalId);
			intervalId = setInterval(() => {
				fs.read('/tmp/AdGuardHome_update.log').then((txt) => {
					if (txt && logTextarea) {
						logTextarea.value = txt;
						logTextarea.scrollTop = logTextarea.scrollHeight;
					}
				}).catch(() => {});

				// 必须检查 update_core
				fs.stat('/var/run/update_core').then(() => {
					// 还在运行中，继续轮询
				}).catch(() => {
					// 文件不存在，说明脚本执行完毕，停止轮询
					clearInterval(intervalId);
					if (btnUpdate) btnUpdate.disabled = false;
					if (btnForce) btnForce.disabled = false;

					// 检查是否有错误文件
					fs.stat('/var/run/update_core_error').then(() => {
						if (btnUpdate) btnUpdate.textContent = _('Failed');
					}).catch(() => {
						if (btnUpdate) btnUpdate.textContent = _('Updated');
						setTimeout(() => { location.reload(); }, 1000);
					});
				});
			}, 1500);
		};

		if (btnUpdate && btnForce && logTextarea) {
			const runUpdate = (force = false) => {
				btnUpdate.disabled = true;
				btnForce.style.display = 'inline-block';
				logTextarea.style.display = 'block';
				btnUpdate.textContent = _('Checking...');
				
				const cmd = force 
                    ? 'touch /var/run/update_core && rm -f /var/run/update_core_error && start-stop-daemon -S -b -q -x /bin/sh -- -c "/usr/share/AdGuardHome/update_core.sh force >/tmp/AdGuardHome_update.log 2>&1"'
                    : 'touch /var/run/update_core && rm -f /var/run/update_core_error && start-stop-daemon -S -b -q -x /bin/sh -- -c "/usr/share/AdGuardHome/update_core.sh >/tmp/AdGuardHome_update.log 2>&1"';
				
				fs.exec('/bin/sh', ['-c', cmd]).then(() => {
					startLogPolling();
				}).catch((err) => {
					btnUpdate.disabled = false;
					logTextarea.value = `[Error] ${err.message || err}`;
				});
			};

			btnUpdate.addEventListener('click', (ev) => { ev.preventDefault(); runUpdate(false); });
			btnForce.addEventListener('click', (ev) => { ev.preventDefault(); runUpdate(true); });
		}

		// 页面初始化时检查是否正在运行
		fs.stat('/var/run/update_core').then(() => {
			if (btnUpdate && btnForce && logTextarea) {
				btnUpdate.disabled = true;
				btnForce.style.display = 'inline-block';
				logTextarea.style.display = 'block';
				btnUpdate.textContent = _('Checking...');
				startLogPolling();
			}
		}).catch(() => {});

		return rendered;
	},
});
