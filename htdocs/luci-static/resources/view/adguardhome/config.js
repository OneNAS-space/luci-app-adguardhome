'use strict';

'require dom';
'require form';
'require fs';
'require poll';
'require rpc';
'require uci';
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

const RUNNING_SPAN = `<span style="color: green; font-weight: bold">${_('Running')}</span>`;
const NOT_RUNNING_SPAN = `<span style="color: red; font-weight: bold">${_('Not running')}</span>`;

const STORAGE_KEY = 'luci-app-adguardhome';
const STORAGE_KEY_CORE = 'luci-app-adguardhome_core_update';

function getServiceInfo(name) {
	const fn = rpc.declare({
		object: 'service',
		method: 'list',
		params: ['name'],
		expect: { [name]: { instances: { [name]: {} }}},
	});
	return function() {
		return fn(name);
	};
}

const getAGHServiceInfo = getServiceInfo('adguardhome');

async function getStatus() {
	try {
		const res = await getAGHServiceInfo();
		const isRunning = res && res.instances && res.instances.adguardhome && res.instances.adguardhome.running;
		return isRunning ? isRunning : false;
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
		return '';
	}
}

function updateStatus(node) {
	const output = node ? node.querySelector('output') : null;
	return output
		? async function() {
			const isRunning = await getStatus();
			dom.content(output, getStatusValue(isRunning));
		}
		: function() {};
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
	load: function() {
		return Promise.all([
			getStatus(),
			getVersion(),
			uci.load('adguardhome').then(function() {
				const sections = uci.sections('adguardhome', 'adguardhome');
				const sec = sections.length > 0 ? sections[0] : {};
				const configFile = sec.config_file || DEFAULT_CONFIG_FILE;
				return fs.read(configFile).catch(function() { return null; });
			})
		]);
	},

	render: async function(data) {
		const isRunning = data[0];
		const version = data[1];
		const yamlContent = data[2];

		const coreExists = Boolean(version);
		let dnsPort = '53';
		if (yamlContent) {
			const portMatches = yamlContent.match(/port:\s*(\d+)/g);
			if (portMatches && portMatches.length >= 2) {
				const actualPort = portMatches[1].match(/\d+/);
				if (actualPort) {
					dnsPort = actualPort[0];
				}
			}
		}

		const sections = uci.sections('adguardhome', 'adguardhome');
		const savedHttpPort = (sections.length > 0 && sections[0].httpport) ? sections[0].httpport : '3008';

		const map = new form.Map('adguardhome', _('AdGuard Home'));

		const statusSect = map.section(form.TypedSection, 'status');
		statusSect.anonymous = true;
		statusSect.cfgsections = function() { return ['status_section']; };

		const versionOpt = statusSect.option(form.DummyValue, '_version', _('Version'));
		versionOpt.cfgvalue = function() {
			return version || '<span style="color: var(--error-color-high); font-weight: bold;">' + _('Not installed') + '</span>';
		};
		versionOpt.rawhtml = true;

		const statusOpt = statusSect.option(form.DummyValue, '_status', _('Service Status'));
		statusOpt.rawhtml = true;
		statusOpt.cfgvalue = function() { return getStatusValue(isRunning); };

		const mainSect = map.section(form.TypedSection, 'adguardhome');
		mainSect.anonymous = true;

		mainSect.tab('general', _('General Settings'));
		mainSect.tab('jail', _('File System Access'), _('Files and directories that AdGuard Home should have read-only or read-write access to.'));
		mainSect.tab('dns_redirect', _('Services Settings'));
		mainSect.tab('core_update', _('Core Update'), _('Settings and operations for updating the AdGuardHome core binary.'));
		mainSect.tab('advanced', _('Advanced Settings'), _('Go environment variables that tune garbage collector and memory management.') + ' ' + _('Modify at your own risk.'));

		const enabledOpt = mainSect.taboption('general', form.Flag, 'enabled', _('Enable'));
		enabledOpt.default = '0';
		enabledOpt.rmempty = false;
		if (!coreExists) {
			enabledOpt.description = '<span style="color: var(--error-color-high); font-weight: bold;">' + _('Core binary not found. Enable the service to trigger an automatic download.') + '</span>';
		}

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
		advSettingsOpt.load = function() { return sessionStorage.getItem(STORAGE_KEY) || '0'; };
		advSettingsOpt.remove = function() {};
		advSettingsOpt.write = function(_, value) { sessionStorage.setItem(STORAGE_KEY, value); };

		const coreUpdateToggleOpt = mainSect.taboption('general', form.Flag, 'enable_core_update', _('Core Update'), _('Show the tab and settings for updating the AdGuardHome core binary.'));
		coreUpdateToggleOpt.default = '0';
		coreUpdateToggleOpt.rmempty = false;
		coreUpdateToggleOpt.load = function() {
			if (sessionStorage.getItem('agh_active_tab') === 'core_update') {
				sessionStorage.setItem(STORAGE_KEY_CORE, '1');
			}
			return sessionStorage.getItem(STORAGE_KEY_CORE) || '0';
		};
		coreUpdateToggleOpt.remove = function() {};
		coreUpdateToggleOpt.write = function(_, value) { sessionStorage.setItem(STORAGE_KEY_CORE, value); };

		mainSect.taboption('jail', form.DynamicList, 'jail_mount', _('Read-only access'));
		mainSect.taboption('jail', form.DynamicList, 'jail_mount_rw', _('Read-write access'));

		const gcOpt = mainSect.taboption('advanced', form.Value, 'gc', 'GOGC');
		gcOpt.datatype = 'uinteger';
		gcOpt.depends('advanced_settings', '1');
		gcOpt.placeholder = DEFAULT_GOGC;
		gcOpt.retain = true;

		const maxProcsOpt = mainSect.taboption('advanced', form.Value, 'maxprocs', 'GOMAXPROCS');
		maxProcsOpt.datatype = 'uinteger';
		maxProcsOpt.depends('advanced_settings', '1');
		maxProcsOpt.placeholder = DEFAULT_GOMAXPROCS;
		maxProcsOpt.retain = true;

		const memLimitOpt = mainSect.taboption('advanced', form.Value, 'memlimit', 'GOMEMLIMIT');
		memLimitOpt.datatype = 'uinteger';
		memLimitOpt.depends('advanced_settings', '1');
		memLimitOpt.placeholder = DEFAULT_GOMEMLIMIT;
		memLimitOpt.retain = true;

		let realHttpAddress = '0.0.0.0:3008';
		if (yamlContent) {
			const addrMatch = yamlContent.match(/address:\s*([^\s]+)/);
			if (addrMatch && addrMatch[1]) realHttpAddress = addrMatch[1];
		}

		let linkIp = window.location.hostname;
		let linkPort = '3008';
		const addrParts = realHttpAddress.split(':');
		if (addrParts.length >= 2) {
			linkPort = addrParts.pop();
			let ipPart = addrParts.join(':').replace(/\[|\]/g, '');
			if (ipPart !== '0.0.0.0' && ipPart !== '') linkIp = ipPart;
		}

		const isServiceEnabled = sections.length > 0 && sections[0].enabled === '1';
		const disabledHint = _('Service is disabled. Please go to "General Settings" to enable it.');

		const webuiBtnHtml = isServiceEnabled
			? '<a class="btn cbi-button cbi-button-link" style="font-weight:bold; display:inline-block; margin-top:5px;" href="http://' + linkIp + ':' + linkPort + '" target="_blank">' + _('Open AdGuardHome WebUI') + '</a>'
			: '<span title="' + disabledHint + '" style="display:inline-block; margin-top:5px; cursor:not-allowed;">' +
					'<a class="btn cbi-button cbi-button-link" style="font-weight:bold; pointer-events:none; opacity:0.5; margin-top:0;" href="javascript:void(0);">' + _('Open AdGuardHome WebUI') + '</a>' +
			  '</span>';

		const httpAddressOpt = mainSect.taboption('dns_redirect', form.Value, 'http_address', _('WebUI listener (address:port)'), '<br />' + webuiBtnHtml);
		httpAddressOpt.placeholder = '0.0.0.0:3008';
		httpAddressOpt.default = '0.0.0.0:3008';
		httpAddressOpt.datatype = 'hostport';
		httpAddressOpt.rmempty = false;
		httpAddressOpt.cfgvalue = function() { return realHttpAddress; };

		const isPasswordEmpty = yamlContent ? /password:[ \t]*(\r?\n|$)/.test(yamlContent) : false;
		const hashPassOpt = mainSect.taboption('dns_redirect', form.Value, 'hashpass', _('Change password'), _('Enter the password here. Click the Load calculate Module button below and go on.') + '<br /><button class="btn cbi-button cbi-button-apply" type="button" id="btn-agh-calc-hash" style="display:inline-block; margin-top:5px;">' + _(' ... Load calculate Module ... ') + '</button>');
		hashPassOpt.default = '';
		hashPassOpt.datatype = 'string';
		hashPassOpt.password = true;
		hashPassOpt.rmempty = true;
		hashPassOpt.placeholder = isPasswordEmpty ? _('Please create a new password.') : '';
		hashPassOpt.cfgvalue = function() { return ''; };

		const redirectOpt = mainSect.taboption('dns_redirect', form.ListValue, 'redirect', dnsPort + ' ' + _('Redirect'), _('AdGuardHome redirect mode'));
		redirectOpt.value('none', _('No redirect'));
		redirectOpt.value('dnsmasq-upstream', _('As the upstream server of dnsmasq'));
		redirectOpt.value('redirect', _('Redirect port 53 to AdGuardHome'));
		redirectOpt.value('exchange', _('Use port 53 to replace dnsmasq'));
		redirectOpt.default = 'none';
		redirectOpt.rmempty = false;

		const coreVersionOpt = mainSect.taboption('core_update', form.ListValue, 'core_version', _('Core Branch'), _('Select the branch for the core binary update.'));
		coreVersionOpt.value('latest', _('Latest Version'));
		coreVersionOpt.value('beta', _('Beta Version'));
		coreVersionOpt.default = 'latest';
		coreVersionOpt.depends('enable_core_update', '1');
		coreVersionOpt.retain = true;

		const coreUrlOpt = mainSect.taboption('core_update', form.ListValue, 'update_url', _('Update URL'), _('Select the download link for the core update.'));
		coreUrlOpt.value('https://static.adtidy.org/adguardhome/release/AdGuardHome_linux_${Arch}.tar.gz', _('Official Mirror (AdTidy - Recommended)'));
		coreUrlOpt.value('https://github.com/AdguardTeam/AdGuardHome/releases/download/${Cloud_Version}/AdGuardHome_linux_${Arch}.tar.gz', _('GitHub Releases (Original)'));
		coreUrlOpt.default = 'https://static.adtidy.org/adguardhome/release/AdGuardHome_linux_${Arch}.tar.gz';
		coreUrlOpt.rmempty = false;
		coreUrlOpt.depends('enable_core_update', '1');
		coreUrlOpt.retain = true;

		const updateActionOpt = mainSect.taboption('core_update', form.DummyValue, '_update_action', _('Action'));
		updateActionOpt.rawhtml = true;
		updateActionOpt.cfgvalue = function() {
			return '<div class="cbi-value-description" style="display: flex; align-items: center; flex-wrap: wrap; gap: 8px;">' +
				'<input class="btn cbi-button cbi-button-apply" type="button" id="btn-agh-action" value="' + _('Check update') + '" />' +
				'<input class="btn cbi-button cbi-button-apply" type="button" id="btn-agh-force" value="' + _('Force update') + '" style="display: none;" />' +
				'<span id="btn-agh-detail" style="font-weight: bold;"></span>' +
			'</div>';
		};
		updateActionOpt.depends('enable_core_update', '1');

		const rendered = await map.render();

		if (sessionStorage.getItem('agh_active_tab') === 'core_update') {
			sessionStorage.removeItem('agh_active_tab');
			window.location.hash = 'core_update';
			window.setTimeout(function() {
				const tabLink = rendered.querySelector('a[href="#cbi-tab-adguardhome-core_update"]') ||
				                rendered.querySelector('a[href="#core_update"]') ||
				                rendered.querySelector('[data-tab="core_update"]');
				if (tabLink) tabLink.click();
			}, 50);
		}

		const statusNode = map.findElement('data-field', statusOpt.cbid('status_section'));
		poll.add(updateStatus(statusNode), POLL_INTERVAL);

		let updatePollId = null;
		let currentState = 'init';

		function startLogPolling() {
			if (updatePollId) clearInterval(updatePollId);

			window.onbeforeunload = function() {
				return _('Updating, are you sure to close?');
			};

			let displayPercent = 0;
			let targetPercent = 0;

			const pollAction = function() {
				const btnAction = document.getElementById('btn-agh-action');
				const btnForce = document.getElementById('btn-agh-force');
				const detail = document.getElementById('btn-agh-detail');

				if (currentState === 'updating') {
					if (displayPercent < targetPercent) {
						displayPercent = Math.min(targetPercent, displayPercent + Math.max(1, Math.ceil((targetPercent - displayPercent) / 3)));
					} else if (displayPercent < 95) {
						targetPercent = Math.min(95, targetPercent + 2);
						displayPercent = Math.min(targetPercent, displayPercent + 1);
					}
					if (btnAction) {
						btnAction.value = _('Updating...') + ' ' + displayPercent + '%';
					}
				}

				fs.read('/tmp/AdGuardHome_update.log').then(function(txt) {
					if (txt && currentState === 'updating') {
						const lines = txt.split('\n');
						let foundPercent = null;
						for (let i = lines.length - 1; i >= 0; i--) {
							const line = lines[i];
							const match = line.match(/^\s*(\d{1,3})\s+[\d\.]+[kMGTP]?\s+/);
							if (match) {
								const p = parseInt(match[1], 10);
								if (p >= 0 && p <= 100) {
									foundPercent = p;
									break;
								}
							}
							const pctMatch = line.match(/(\d{1,3})%/);
							if (pctMatch) {
								const p = parseInt(pctMatch[1], 10);
								if (p >= 0 && p <= 100) {
									foundPercent = p;
									break;
								}
							}
						}

						if (foundPercent !== null && foundPercent > targetPercent) {
							targetPercent = foundPercent;
						}
					}
				}).catch(function() {});

				Promise.all([
					fs.stat('/var/run/update_core').catch(function() { return null; }),
					fs.stat('/var/run/update_core_done').catch(function() { return null; }),
					fs.stat('/var/run/update_core_error').catch(function() { return null; })
				]).then(function(results) {
					const isDone = results[1];
					const isError = results[2];

					if (isDone) {
						clearInterval(updatePollId);
						fs.remove('/var/run/update_core_done').catch(function() {});
						window.onbeforeunload = undefined;
						currentState = 'success';
						
						displayPercent = 100;
						if (btnAction) {
							btnAction.value = _('Updating...') + ' 100%';
							btnAction.disabled = true;
						}

						window.setTimeout(function() {
							if (btnAction) {
								btnAction.value = _('Update successful');
							}
							if (btnForce) btnForce.style.display = 'none';
							if (detail) detail.textContent = '';
							
							sessionStorage.setItem('agh_active_tab', 'core_update');
							sessionStorage.setItem(STORAGE_KEY_CORE, '1');
							window.location.hash = 'core_update';

							window.setTimeout(function() {
								window.location.reload();
							}, 800);
						}, 300);

					} else if (isError) {
						clearInterval(updatePollId);
						window.onbeforeunload = undefined;
						currentState = 'failed';
						if (btnAction) {
							btnAction.value = _('Retry');
							btnAction.disabled = false;
						}
						if (btnForce) {
							btnForce.style.display = 'inline-block';
							btnForce.disabled = false;
						}
						if (detail) {
							detail.innerHTML = '<span style="color: red;">' + _('Update failed') + '</span>';
						}
					}
				});
			};

			pollAction();
			updatePollId = setInterval(pollAction, 250);
		}

		function triggerCheck() {
			const btnAction = document.getElementById('btn-agh-action');
			const btnForce = document.getElementById('btn-agh-force');
			const detail = document.getElementById('btn-agh-detail');

			currentState = 'checking';
			if (btnAction) {
				btnAction.value = _('Checking...');
				btnAction.disabled = true;
			}
			if (detail) detail.textContent = '';

			fetch('https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest')
				.then(function(res) { return res.json(); })
				.then(function(data) {
					const remoteVersion = (data && data.tag_name) ? data.tag_name : null;
					if (!remoteVersion) {
						throw new Error('Invalid version data');
					}
					const cleanLocal = coreExists ? version.replace(/^v/, '') : '';
					const cleanRemote = remoteVersion.replace(/^v/, '');

					if (!coreExists || cleanLocal !== cleanRemote) {
						currentState = 'updatable';
						if (btnAction) {
							btnAction.value = _('Click to update');
							btnAction.disabled = false;
						}
						if (btnForce) {
							btnForce.style.display = 'none';
						}
						if (detail) {
							let urlNode = '<em style="color: red;">' + remoteVersion + '</em>';
							if (data && data.html_url) {
								urlNode = '<a href="' + data.html_url + '" target="_blank">' + urlNode + '</a>';
							}
							detail.innerHTML = urlNode;
						}
					} else {
						currentState = 'latest';
						if (btnAction) {
							btnAction.value = _('It is the latest version');
							btnAction.disabled = true;
						}
						if (btnForce) {
							btnForce.style.display = 'inline-block';
							btnForce.disabled = false;
						}
						if (detail) {
							detail.innerHTML = '';
						}
					}
				})
				.catch(function() {
					currentState = 'check_failed';
					if (btnAction) {
						btnAction.value = _('Retry');
						btnAction.disabled = false;
					}
					if (btnForce) {
						btnForce.style.display = 'none';
					}
					if (detail) {
						detail.innerHTML = '<em style="color: red;">' + _('Check failed') + '</em>';
					}
				});
		}

		function triggerUpdate(isForce) {
			const btnAction = document.getElementById('btn-agh-action');
			const btnForce = document.getElementById('btn-agh-force');

			currentState = 'updating';
			if (btnAction) {
				btnAction.disabled = true;
				btnAction.value = _('Updating...') + ' 0%';
			}
			if (btnForce) btnForce.disabled = true;

			try {
				const coreVersionEl = document.querySelector('select[data-name="core_version"]');
				const updateUrlEl = document.querySelector('select[data-name="update_url"]');
				const adguardSections = uci.sections('adguardhome', 'adguardhome');
				const secId = adguardSections.length > 0 ? adguardSections[0]['.name'] : null;
				if (secId) {
					if (coreVersionEl) uci.set('adguardhome', secId, 'core_version', coreVersionEl.value);
					if (updateUrlEl) uci.set('adguardhome', secId, 'update_url', updateUrlEl.value);
					uci.save();
				}
			} catch (err) {
				console.error('Silent UCI save failed:', err);
			}

			const arg = isForce ? 'force' : '';
			fs.exec('/usr/share/AdGuardHome/update_core.sh', [arg]).catch(function(err) {
				console.error('Failed to trigger update script:', err);
			});
			startLogPolling();
		}

		rendered.addEventListener('click', function(e) {
			if (e.target && (e.target.id === 'btn-agh-action' || e.target.id === 'btn-agh-force')) {
				e.preventDefault();
				e.stopPropagation();
				e.stopImmediatePropagation();

				if (e.target.id === 'btn-agh-action') {
					if (currentState === 'init' || currentState === 'check_failed') {
						triggerCheck();
					} else if (currentState === 'updatable' || currentState === 'failed') {
						triggerUpdate(false);
					}
				} else if (e.target.id === 'btn-agh-force') {
					triggerUpdate(true);
				}
			} else if (e.target && e.target.id === 'btn-agh-calc-hash') {
				e.preventDefault();
				e.stopPropagation();
				e.stopImmediatePropagation();

				const btn = e.target;
				const inputs = rendered.querySelectorAll('input[type="text"], input[type="password"]');
				let passInput = null;
				for (let i = 0; i < inputs.length; i++) {
					if (inputs[i].id && inputs[i].id.endsWith('.hashpass')) {
						passInput = inputs[i];
						break;
					}
				}
				if (!passInput) return;

				if (typeof window.TwinBcrypt === 'undefined') {
					btn.disabled = true;
					btn.textContent = _('Loading...');
					const script = document.createElement('script');
					script.src = L.resource('view/adguardhome/twin-bcrypt.min.js');
					script.type = 'text/javascript';
					script.onload = function() {
						btn.textContent = _('Click here to Calculate');
						btn.disabled = false;
					};
					script.onerror = function() {
						btn.textContent = _(' ... Load Error ... ');
						btn.disabled = false;
					};
					document.head.appendChild(script);
				} else {
					if (passInput.value) {
						if (passInput.value.startsWith('$2a$') || passInput.value.startsWith('$2y$')) {
							btn.textContent = _('Calculation already DONE !');
							return;
						}
						const hash = window.TwinBcrypt.hashSync(passInput.value);
						passInput.value = hash;
						passInput.dispatchEvent(new Event('input', { bubbles: true }));
						passInput.dispatchEvent(new Event('change', { bubbles: true }));
						btn.textContent = _(' ... Click Save/Apply ↘️ ... ');
					} else {
						btn.textContent = _(' ... Nothing inputted yet ... ');
					}
				}
			}
		});

		Promise.all([
			fs.stat('/var/run/update_core').catch(function() { return null; }),
			fs.stat('/var/run/update_core_error').catch(function() { return null; })
		]).then(function(results) {
			const isCore = results[0];
			const isError = results[1];
			if (isCore || isError) {
				const btnAction = document.getElementById('btn-agh-action');
				currentState = 'updating';
				if (btnAction) {
					btnAction.value = _('Updating...') + ' 0%';
					btnAction.disabled = true;
				}
				startLogPolling();
			}
		});

		return rendered;
	}
});
