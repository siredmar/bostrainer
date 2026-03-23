// BOS-Funk Trainer Client

class BOSTrainer {
    constructor() {
        this.ws = null;
        this.mediaRecorder = null;
        this.audioChunks = [];
        this.isRecording = false;
        this.currentScenario = null;
        this.audioContext = null;

        this.elements = {
            scenarioSelection: document.getElementById('scenario-selection'),
            scenarioList: document.getElementById('scenario-list'),
            briefingSection: document.getElementById('briefing-section'),
            briefingContent: document.getElementById('briefing-content'),
            userRole: document.getElementById('user-role'),
            aiRole: document.getElementById('ai-role'),
            firstHint: document.getElementById('first-hint'),
            trainingSection: document.getElementById('training-section'),
            transcriptLog: document.getElementById('transcript-log'),
            pttButton: document.getElementById('ptt-button'),
            endButton: document.getElementById('end-button'),
            status: document.getElementById('status'),
            evaluationSection: document.getElementById('evaluation-section'),
            evaluationContent: document.getElementById('evaluation-content'),
            restartButton: document.getElementById('restart-button'),
            connectionStatus: document.getElementById('connection-status'),
            backButton: document.getElementById('back-button'),
            headerTitle: document.getElementById('header-title'),
        };

        this.init();
    }

    init() {
        this.connect();
        this.setupEventListeners();
        this.initAudioContext();
    }

    // Initialize AudioContext for radio filter effect
    initAudioContext() {
        this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
    }

    // Create radio bandpass filter chain (300Hz - 3000Hz typical for BOS radio)
    createRadioFilter() {
        const ctx = this.audioContext;
        
        // High-pass filter at 300Hz
        const highpass = ctx.createBiquadFilter();
        highpass.type = 'highpass';
        highpass.frequency.value = 300;
        highpass.Q.value = 0.7;

        // Low-pass filter at 3000Hz
        const lowpass = ctx.createBiquadFilter();
        lowpass.type = 'lowpass';
        lowpass.frequency.value = 3000;
        lowpass.Q.value = 0.7;

        // Slight distortion/compression for radio effect
        const compressor = ctx.createDynamicsCompressor();
        compressor.threshold.value = -20;
        compressor.knee.value = 10;
        compressor.ratio.value = 4;
        compressor.attack.value = 0.005;
        compressor.release.value = 0.1;

        // Chain: source -> highpass -> lowpass -> compressor -> destination
        highpass.connect(lowpass);
        lowpass.connect(compressor);

        return { input: highpass, output: compressor };
    }

    // Play a short click/squelch sound (typical radio PTT sound)
    playRadioClick() {
        if (!this.audioContext) return;
        
        const ctx = this.audioContext;
        const oscillator = ctx.createOscillator();
        const gain = ctx.createGain();
        
        oscillator.type = 'square';
        oscillator.frequency.value = 1200;
        
        gain.gain.setValueAtTime(0.15, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.05);
        
        oscillator.connect(gain);
        gain.connect(ctx.destination);
        
        oscillator.start(ctx.currentTime);
        oscillator.stop(ctx.currentTime + 0.05);
    }

    connect() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/ws`;
        
        this.updateConnectionStatus('connecting');
        
        this.ws = new WebSocket(wsUrl);
        
        this.ws.onopen = () => {
            console.log('WebSocket connected');
            this.updateConnectionStatus('connected');
            this.ws.send(JSON.stringify({ type: 'list_scenarios' }));
        };
        
        this.ws.onclose = (event) => {
            console.log('WebSocket disconnected, code:', event.code, 'reason:', event.reason);
            this.updateConnectionStatus('disconnected');
            
            // Don't reconnect if on evaluation screen (session complete)
            if (!this.elements.evaluationSection.classList.contains('hidden')) {
                console.log('On evaluation screen, not reconnecting');
                return;
            }
            
            // Auto-reconnect after 3 seconds
            setTimeout(() => this.connect(), 3000);
        };
        
        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
        
        this.ws.onmessage = (event) => {
            const msg = JSON.parse(event.data);
            this.handleMessage(msg);
        };
    }

    handleMessage(msg) {
        console.log('Received:', msg.type, msg);
        
        switch (msg.type) {
            case 'scenarios':
                this.displayScenarios(msg.scenarios);
                break;
            case 'session_started':
                this.onSessionStarted(msg);
                break;
            case 'demo_started':
                this.onDemoStarted(msg);
                break;
            case 'demo_line':
                this.onDemoLine(msg);
                break;
            case 'demo_complete':
                this.onDemoComplete();
                break;
            case 'response':
                this.onResponse(msg);
                break;
            case 'evaluation':
                this.onEvaluation(msg);
                break;
            case 'status':
                this.onStatus(msg);
                break;
            case 'error':
                this.showError(msg.message);
                break;
        }
    }

    onStatus(msg) {
        let statusText = msg.status || '';
        if (msg.progress) {
            statusText += ` (${msg.progress})`;
        }
        this.setStatus(statusText);
    }

    displayScenarios(scenarios) {
        // Group scenarios by category
        const categories = {};
        scenarios.forEach(s => {
            const cat = s.category || 'Einsatz-Szenarien';
            if (!categories[cat]) categories[cat] = [];
            categories[cat].push(s);
        });

        const categoryNames = Object.keys(categories);
        
        // Build tabs + content
        let tabsHtml = '<div class="category-tabs">';
        let contentHtml = '';
        
        categoryNames.forEach((cat, idx) => {
            const tabId = `cat-${idx}`;
            tabsHtml += `<button class="category-tab ${idx === 0 ? 'active' : ''}" data-tab="${tabId}">${cat}</button>`;
            
            const items = categories[cat].map(s => `
                <div class="scenario-item ${s.is_demo ? 'demo' : ''}" data-key="${s.key}" data-demo="${s.is_demo}">
                    <div class="name">${s.name}</div>
                    <div class="description">${s.description}</div>
                    <div class="roles-preview">${s.is_demo ? '🎧 Demo zum Anhören' : `Du: ${s.user_role} | Gegenstelle: ${s.ai_role}`}</div>
                </div>
            `).join('');
            
            contentHtml += `<div class="category-content ${idx === 0 ? '' : 'hidden'}" id="${tabId}">${items}</div>`;
        });
        
        tabsHtml += '</div>';
        this.elements.scenarioList.innerHTML = tabsHtml + contentHtml;

        // Tab switching
        this.elements.scenarioList.querySelectorAll('.category-tab').forEach(tab => {
            tab.addEventListener('click', () => {
                this.elements.scenarioList.querySelectorAll('.category-tab').forEach(t => t.classList.remove('active'));
                this.elements.scenarioList.querySelectorAll('.category-content').forEach(c => c.classList.add('hidden'));
                tab.classList.add('active');
                document.getElementById(tab.dataset.tab).classList.remove('hidden');
            });
        });

        // Scenario click handlers
        this.elements.scenarioList.querySelectorAll('.scenario-item').forEach(item => {
            item.addEventListener('click', () => {
                const key = item.dataset.key;
                const isDemo = item.dataset.demo === 'true';
                if (isDemo) {
                    this.startDemo(key);
                } else {
                    this.startSession(key);
                }
            });
        });
    }

    startSession(scenarioKey) {
        this.ws.send(JSON.stringify({
            type: 'start_session',
            scenario_key: scenarioKey
        }));
        this.setStatus('Szenario wird geladen...');
    }

    startDemo(scenarioKey) {
        this.ws.send(JSON.stringify({
            type: 'start_demo',
            scenario_key: scenarioKey
        }));
        this.setStatus('Demo wird generiert...');
        this.demoQueue = [];
        this.isPlayingDemo = false;
    }

    onDemoStarted(msg) {
        this.currentScenario = msg;
        this.isDemo = true;
        
        this.elements.briefingContent.textContent = msg.briefing;
        this.elements.userRole.textContent = msg.user_role;
        this.elements.aiRole.textContent = msg.ai_role;
        this.elements.firstHint.textContent = '🎧 Demo läuft - bitte zuhören...';
        
        this.elements.scenarioSelection.classList.add('hidden');
        this.elements.briefingSection.classList.remove('hidden');
        this.elements.trainingSection.classList.remove('hidden');
        this.elements.backButton.classList.remove('hidden');
        this.elements.transcriptLog.innerHTML = '';
        
        // Hide PTT button in demo mode
        this.elements.pttButton.style.display = 'none';
        this.elements.endButton.textContent = 'Demo beenden';
        this.elements.endButton.disabled = false;
        
        this.setStatus('🎧 Demo wird abgespielt...');
    }

    onDemoLine(msg) {
        if (msg.demo_lines && msg.demo_lines.length > 0) {
            const line = msg.demo_lines[0];
            this.demoQueue.push(line);
            this.playNextDemoLine();
        }
    }

    async playNextDemoLine() {
        if (this.isPlayingDemo || this.demoQueue.length === 0) return;
        
        this.isPlayingDemo = true;
        const line = this.demoQueue.shift();
        
        // Add to transcript
        this.addTranscriptEntry('ai', line.speaker, line.text);
        
        // Play audio if available
        if (line.audio) {
            await this.playAudioAndWait(line.audio);
        }
        
        // Small pause between lines
        await new Promise(resolve => setTimeout(resolve, 800));
        
        this.isPlayingDemo = false;
        this.playNextDemoLine();
    }

    async playAudioAndWait(base64Audio) {
        return new Promise(async (resolve) => {
            try {
                if (this.audioContext.state === 'suspended') {
                    await this.audioContext.resume();
                }

                this.playRadioClick();
                
                const audioData = Uint8Array.from(atob(base64Audio), c => c.charCodeAt(0));
                const arrayBuffer = audioData.buffer;
                const audioBuffer = await this.audioContext.decodeAudioData(arrayBuffer.slice(0));
                
                const source = this.audioContext.createBufferSource();
                source.buffer = audioBuffer;
                
                const filter = this.createRadioFilter();
                source.connect(filter.input);
                filter.output.connect(this.audioContext.destination);
                
                source.onended = resolve;
                source.start(0);
            } catch (e) {
                console.error('Demo audio error:', e);
                resolve();
            }
        });
    }

    onDemoComplete() {
        this.setStatus('🎧 Demo beendet');
        this.elements.endButton.textContent = 'Zurück zur Auswahl';
    }

    onSessionStarted(msg) {
        this.currentScenario = msg;
        this.isDemo = false;
        
        this.elements.briefingContent.textContent = msg.briefing;
        this.elements.userRole.textContent = msg.user_role;
        this.elements.aiRole.textContent = msg.ai_role;
        this.elements.firstHint.textContent = msg.first_hint || '';
        
        this.elements.scenarioSelection.classList.add('hidden');
        this.elements.briefingSection.classList.remove('hidden');
        this.elements.trainingSection.classList.remove('hidden');
        this.elements.backButton.classList.remove('hidden');
        this.elements.transcriptLog.innerHTML = '';
        
        // Show PTT button for interactive mode
        this.elements.pttButton.style.display = '';
        
        this.elements.pttButton.disabled = false;
        this.elements.endButton.disabled = false;
        
        this.setStatus('Bereit - Drücke den Knopf zum Sprechen');
    }

    onResponse(msg) {
        // Add user message
        if (msg.transcript) {
            this.addTranscriptEntry('user', 'DU', msg.transcript);
        }
        
        // Add AI response (only if there is one - not for "Ende" messages)
        if (msg.reply) {
            this.addTranscriptEntry('ai', this.currentScenario?.ai_role || 'GEGENSTELLE', msg.reply);
        }
        
        // If no reply and no audio: this is an "Ende" response, evaluation follows
        if (!msg.reply && !msg.audio) {
            this.elements.pttButton.disabled = true;
            this.elements.endButton.disabled = true;
            this.setStatus('Auswertung wird erstellt...', 'processing');
            return;
        }
        
        // Play audio if available
        if (msg.audio) {
            this.playAudio(msg.audio);
        } else {
            this.setStatus('Bereit');
            this.elements.pttButton.disabled = false;
        }
    }

    onEvaluation(msg) {
        console.log('onEvaluation called with:', JSON.stringify(msg, null, 2));
        
        // Disable PTT and end button
        this.elements.pttButton.disabled = true;
        this.elements.endButton.disabled = true;
        
        // Keep training section visible - show evaluation inline
        if (msg.evaluation) {
            this.renderInlineEvaluation(msg.evaluation);
        } else if (msg.analysis) {
            this.appendEvaluationSummary(msg.analysis);
        } else {
            this.appendEvaluationSummary('Keine Auswertung verfügbar.');
        }
    }

    renderInlineEvaluation(evaluation) {
        // Attach per-message evaluations as collapsibles under the corresponding transcript entries
        if (evaluation.messages && evaluation.messages.length > 0) {
            const userEntries = this.elements.transcriptLog.querySelectorAll('.transcript-entry.user');
            
            evaluation.messages.forEach((msg, idx) => {
                const msgNumber = msg.number || (idx + 1);
                const targetEntry = userEntries[msgNumber - 1];
                if (!targetEntry) return;
                
                const scoreColor = this.getScoreColor(msg.score);
                const collapsible = document.createElement('div');
                collapsible.className = 'eval-collapsible';
                collapsible.innerHTML = `
                    <button class="eval-toggle" onclick="this.parentElement.classList.toggle('open')">
                        <span class="eval-toggle-score" style="background:${scoreColor}">${msg.score}%</span>
                        <span class="eval-toggle-label">Auswertung</span>
                        <span class="eval-toggle-arrow">▶</span>
                    </button>
                    <div class="eval-details">
                        ${msg.correct && msg.correct.length > 0 ? 
                            `<div class="msg-correct">✅ ${msg.correct.join('<br>✅ ')}</div>` : ''}
                        ${msg.improvements && msg.improvements.length > 0 ? 
                            `<div class="msg-improvements">⚠️ ${msg.improvements.join('<br>⚠️ ')}</div>` : ''}
                        ${msg.errors && msg.errors.length > 0 ? 
                            `<div class="msg-errors">❌ ${msg.errors.join('<br>❌ ')}</div>` : ''}
                        ${msg.improved ? 
                            `<div class="msg-improved"><strong>💡 Besser:</strong> "${msg.improved}"</div>` : ''}
                    </div>
                `;
                targetEntry.after(collapsible);
            });
        }

        // Append summary at the bottom of the transcript
        const scoreColor = this.getScoreColor(evaluation.overall_score);
        let summaryHtml = `
            <div class="eval-summary-block">
                <div class="eval-summary-header">
                    <h3>🔍 Auswertung</h3>
                    <div class="eval-overall-badge" style="background:${scoreColor}">${evaluation.overall_score}%</div>
                </div>
                <div class="eval-summary-text">${evaluation.summary || ''}</div>
        `;
        
        if (evaluation.tips && evaluation.tips.length > 0) {
            summaryHtml += `
                <div class="eval-tips-inline">
                    <strong>💡 Tipps:</strong>
                    <ol>${evaluation.tips.map(t => `<li>${t}</li>`).join('')}</ol>
                </div>
            `;
        }
        
        summaryHtml += `
                <button class="restart-button" onclick="document.getElementById('restart-trigger').click()">Neues Training</button>
            </div>
        `;
        
        const summaryDiv = document.createElement('div');
        summaryDiv.innerHTML = summaryHtml;
        this.elements.transcriptLog.appendChild(summaryDiv);
        
        // Remove max-height limit so full evaluation is scrollable
        this.elements.transcriptLog.style.maxHeight = 'none';
        this.elements.transcriptLog.scrollTop = this.elements.transcriptLog.scrollHeight;
    }

    appendEvaluationSummary(text) {
        const summaryDiv = document.createElement('div');
        summaryDiv.innerHTML = `
            <div class="eval-summary-block">
                <h3>🔍 Auswertung</h3>
                <div class="eval-summary-text">${text}</div>
                <button class="restart-button" onclick="document.getElementById('restart-trigger').click()">Neues Training</button>
            </div>
        `;
        this.elements.transcriptLog.appendChild(summaryDiv);
        this.elements.transcriptLog.style.maxHeight = 'none';
        this.elements.transcriptLog.scrollTop = this.elements.transcriptLog.scrollHeight;
    }

    getScoreColor(score) {
        if (score >= 80) return '#28a745'; // Green
        if (score >= 50) return '#ffc107'; // Yellow
        return '#dc3545'; // Red
    }

    addTranscriptEntry(type, role, content) {
        const entry = document.createElement('div');
        entry.className = `transcript-entry ${type}`;
        // Track user message index for evaluation matching
        if (type === 'user') {
            if (!this.userMessageCount) this.userMessageCount = 0;
            this.userMessageCount++;
            entry.dataset.userMsgIndex = this.userMessageCount;
        }
        entry.innerHTML = `
            <div class="role-label">${role}</div>
            <div class="content">${content}</div>
        `;
        this.elements.transcriptLog.appendChild(entry);
        this.elements.transcriptLog.scrollTop = this.elements.transcriptLog.scrollHeight;
    }

    async playAudio(base64Audio) {
        this.setStatus('Wiedergabe...', 'playing');
        
        try {
            // Play radio click before voice
            this.playRadioClick();
            // Resume AudioContext if suspended (browser autoplay policy)
            if (this.audioContext.state === 'suspended') {
                await this.audioContext.resume();
            }

            const audioData = Uint8Array.from(atob(base64Audio), c => c.charCodeAt(0));
            const arrayBuffer = audioData.buffer;
            
            // Decode audio data
            const audioBuffer = await this.audioContext.decodeAudioData(arrayBuffer.slice(0));
            
            // Create source
            const source = this.audioContext.createBufferSource();
            source.buffer = audioBuffer;
            
            // Create radio filter chain
            const filter = this.createRadioFilter();
            
            // Connect: source -> filter -> destination
            source.connect(filter.input);
            filter.output.connect(this.audioContext.destination);
            
            source.onended = () => {
                this.setStatus('Bereit');
                this.elements.pttButton.disabled = false;
            };
            
            source.start(0);
        } catch (e) {
            console.error('Audio playback error:', e);
            this.setStatus('Bereit');
            this.elements.pttButton.disabled = false;
        }
    }

    setupEventListeners() {
        // Push-to-talk button
        const ptt = this.elements.pttButton;
        
        // Mouse events
        ptt.addEventListener('mousedown', (e) => {
            e.preventDefault();
            this.startRecording();
        });
        ptt.addEventListener('mouseup', () => this.stopRecording());
        ptt.addEventListener('mouseleave', () => {
            if (this.isRecording) this.stopRecording();
        });
        
        // Touch events for mobile
        ptt.addEventListener('touchstart', (e) => {
            e.preventDefault();
            this.startRecording();
        });
        ptt.addEventListener('touchend', (e) => {
            e.preventDefault();
            this.stopRecording();
        });
        ptt.addEventListener('touchcancel', () => {
            if (this.isRecording) this.stopRecording();
        });

        // End button
        this.elements.endButton.addEventListener('click', () => {
            if (this.isDemo) {
                // Demo mode - just go back to selection
                this.resetToSelection();
            } else {
                // Interactive mode - request evaluation
                this.ws.send(JSON.stringify({ type: 'end_session' }));
                this.elements.pttButton.disabled = true;
                this.elements.endButton.disabled = true;
                this.setStatus('Auswertung wird erstellt...');
            }
        });

        // Restart button (hidden trigger for inline evaluation)
        document.getElementById('restart-trigger').addEventListener('click', () => {
            this.resetToSelection();
        });
        if (this.elements.restartButton) {
            this.elements.restartButton.addEventListener('click', () => {
                this.resetToSelection();
            });
        }

        // Back button and header title → return to main menu
        this.elements.backButton.addEventListener('click', () => this.goBack());
        this.elements.headerTitle.addEventListener('click', () => this.goBack());
    }

    goBack() {
        // If in a session, end it first
        if (this.currentScenario && !this.elements.pttButton.disabled) {
            this.ws.send(JSON.stringify({ type: 'end_session' }));
        }
        this.resetToSelection();
    }

    resetToSelection() {
        this.elements.evaluationSection.classList.add('hidden');
        this.elements.trainingSection.classList.add('hidden');
        this.elements.briefingSection.classList.add('hidden');
        this.elements.scenarioSelection.classList.remove('hidden');
        this.elements.backButton.classList.add('hidden');
        this.elements.pttButton.style.display = '';
        this.elements.endButton.textContent = 'Training beenden';
        this.elements.transcriptLog.style.maxHeight = '';
        this.currentScenario = null;
        this.isDemo = false;
        this.demoQueue = [];
        this.userMessageCount = 0;
    }

    async startRecording() {
        if (this.isRecording || this.elements.pttButton.disabled) return;
        
        try {
            // Resume AudioContext if suspended
            if (this.audioContext.state === 'suspended') {
                await this.audioContext.resume();
            }

            const stream = await navigator.mediaDevices.getUserMedia({ 
                audio: {
                    sampleRate: 16000,
                    channelCount: 1,
                    echoCancellation: true,
                    noiseSuppression: true
                }
            });
            
            // Create filtered stream through radio bandpass filter
            const filteredStream = this.createFilteredStream(stream);
            
            this.audioChunks = [];
            this.mediaRecorder = new MediaRecorder(filteredStream, {
                mimeType: this.getSupportedMimeType()
            });
            
            this.mediaRecorder.ondataavailable = (event) => {
                if (event.data.size > 0) {
                    this.audioChunks.push(event.data);
                }
            };
            
            // Store original stream to stop tracks later
            this.originalStream = stream;
            
            this.mediaRecorder.onstop = () => {
                this.originalStream.getTracks().forEach(track => track.stop());
                this.sendAudio();
            };
            
            // Play radio click when starting to record
            this.playRadioClick();
            
            this.mediaRecorder.start();
            this.isRecording = true;
            this.elements.pttButton.classList.add('recording');
            this.setStatus('⏺ Aufnahme läuft...', 'recording');
            
        } catch (e) {
            console.error('Microphone access error:', e);
            this.showError('Mikrofon-Zugriff verweigert. Bitte erlaube den Zugriff.');
        }
    }

    // Create a filtered audio stream with radio bandpass effect
    createFilteredStream(inputStream) {
        const ctx = this.audioContext;
        const source = ctx.createMediaStreamSource(inputStream);
        
        // High-pass filter at 300Hz
        const highpass = ctx.createBiquadFilter();
        highpass.type = 'highpass';
        highpass.frequency.value = 300;
        highpass.Q.value = 0.7;

        // Low-pass filter at 3000Hz
        const lowpass = ctx.createBiquadFilter();
        lowpass.type = 'lowpass';
        lowpass.frequency.value = 3000;
        lowpass.Q.value = 0.7;

        // Compression for radio effect
        const compressor = ctx.createDynamicsCompressor();
        compressor.threshold.value = -20;
        compressor.knee.value = 10;
        compressor.ratio.value = 4;
        compressor.attack.value = 0.005;
        compressor.release.value = 0.1;

        // Create output destination
        const destination = ctx.createMediaStreamDestination();

        // Chain: source -> highpass -> lowpass -> compressor -> destination
        source.connect(highpass);
        highpass.connect(lowpass);
        lowpass.connect(compressor);
        compressor.connect(destination);

        return destination.stream;
    }

    stopRecording() {
        if (!this.isRecording || !this.mediaRecorder) return;
        
        this.mediaRecorder.stop();
        this.isRecording = false;
        this.elements.pttButton.classList.remove('recording');
        this.setStatus('Verarbeite...', 'processing');
        this.elements.pttButton.disabled = true;
    }

    async sendAudio() {
        if (this.audioChunks.length === 0) {
            this.setStatus('Keine Aufnahme erkannt');
            this.elements.pttButton.disabled = false;
            return;
        }

        const audioBlob = new Blob(this.audioChunks, { type: this.getSupportedMimeType() });
        
        // Convert to base64 safely (avoid stack overflow with large arrays)
        const arrayBuffer = await audioBlob.arrayBuffer();
        const uint8Array = new Uint8Array(arrayBuffer);
        
        // Process in chunks to avoid call stack overflow
        let binary = '';
        const chunkSize = 8192;
        for (let i = 0; i < uint8Array.length; i += chunkSize) {
            const chunk = uint8Array.subarray(i, i + chunkSize);
            binary += String.fromCharCode.apply(null, chunk);
        }
        const base64 = btoa(binary);
        
        this.ws.send(JSON.stringify({
            type: 'audio',
            data: base64
        }));
    }

    getSupportedMimeType() {
        const types = [
            'audio/webm;codecs=opus',
            'audio/webm',
            'audio/ogg;codecs=opus',
            'audio/wav'
        ];
        for (const type of types) {
            if (MediaRecorder.isTypeSupported(type)) {
                return type;
            }
        }
        return 'audio/webm';
    }

    setStatus(text, type = '') {
        this.elements.status.textContent = text;
        this.elements.status.className = 'status ' + type;
    }

    updateConnectionStatus(status) {
        const el = this.elements.connectionStatus;
        el.className = 'connection-status ' + status;
        
        const texts = {
            connected: 'Verbunden',
            disconnected: 'Nicht verbunden',
            connecting: 'Verbinde...'
        };
        el.querySelector('.text').textContent = texts[status];
    }

    showError(message) {
        alert('Fehler: ' + message);
    }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    new BOSTrainer();
});
