(() => {
  const RESOURCE = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'st_dealership';

  const state = {
    ctx: null,
    view: 'showroom',
    inventory: [],
    currentVehicle: null,
    tradeInOffer: null,
  };

  // Dealership name/slug -> label, for rendering trade offers from/to
  // dealerships that aren't the one currently open. Populated in loadTrade().
  let dealershipNameCache = {};

  // ---------------------------------------------------------------------
  // NUI bridge
  // ---------------------------------------------------------------------
  async function nui(action, data) {
    try {
      const res = await fetch(`https://${RESOURCE}/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
      });
      return await res.json();
    } catch (e) {
      // allows viewing/testing the UI in a normal browser
      return null;
    }
  }

  window.addEventListener('message', (event) => {
    const { action, data } = event.data || {};
    if (action === 'open') openApp(data);
    if (action === 'close') hideApp();
    if (action === 'placementResult') handlePlacementResult(data);
    if (action === 'downscalePhoto') downscalePhoto(data);
    if (action === 'openAdmin') openAdmin(data);
    if (action === 'closeAdmin') hideAdmin();
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { nui('close'); hideApp(); hideAdmin(); }
  });

  // ---------------------------------------------------------------------
  // Photo downscaling
  //
  // screenshot-basic captures at the player's native resolution, so on a
  // 1440p or 4K monitor even a low-quality JPEG data URI is far too big to
  // travel to the server inside a callback event. Lua has no image
  // decoder, but this page does: the capture gets drawn into a canvas at a
  // bounded width and re-encoded as JPEG, which gets it under the limit
  // regardless of what the player's display is.
  //
  // This runs whether or not the interface is visible - the NUI page stays
  // loaded, and fetch() back to Lua does not need focus.
  // ---------------------------------------------------------------------
  function downscalePhoto({ dataUri, maxWidth, quality } = {}) {
    if (!dataUri) { nui('photoDownscaled', { error: 'no image data' }); return; }

    const img = new Image();

    img.onload = () => {
      try {
        const targetWidth = maxWidth || 960;
        const scale = Math.min(1, targetWidth / (img.width || targetWidth));

        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round((img.width || targetWidth) * scale));
        canvas.height = Math.max(1, Math.round((img.height || targetWidth * 0.5625) * scale));

        const ctx = canvas.getContext('2d');
        ctx.imageSmoothingEnabled = true;
        ctx.imageSmoothingQuality = 'high';
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);

        nui('photoDownscaled', {
          dataUri: canvas.toDataURL('image/jpeg', typeof quality === 'number' ? quality : 0.6),
          width: canvas.width,
          height: canvas.height,
        });
      } catch (e) {
        nui('photoDownscaled', { error: String(e) });
      }
    };

    img.onerror = () => nui('photoDownscaled', { error: 'the capture could not be decoded' });
    img.src = dataUri;
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  function money(n) {
    n = Math.round(Number(n) || 0);
    return (state.ctx?.currencySymbol || '$') + n.toLocaleString('en-US');
  }

  function titleCase(s) {
    return String(s || '').replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
  }

  function conditionClass(avg) {
    if (avg >= 90) return 'cond-excellent';
    if (avg >= 75) return 'cond-good';
    if (avg >= 50) return 'cond-fair';
    return 'cond-poor';
  }
  function conditionLabel(avg) {
    if (avg >= 90) return 'Excellent';
    if (avg >= 75) return 'Good';
    if (avg >= 50) return 'Fair';
    return 'Needs work';
  }
  function averageCondition(conditions) {
    const vals = Object.values(conditions || {});
    if (!vals.length) return 100;
    return Math.round(vals.reduce((a, b) => a + Number(b), 0) / vals.length);
  }
  function parseConditions(raw) {
    if (!raw) return {};
    if (typeof raw === 'object') return raw;
    try { return JSON.parse(raw); } catch (e) { return {}; }
  }

  function getVehiclePhoto(v) {
    if (!v.photos_json) return null;
    try {
      const photos = typeof v.photos_json === 'string' ? JSON.parse(v.photos_json) : v.photos_json;
      return (Array.isArray(photos) && photos[0]) || null;
    } catch (e) {
      return null;
    }
  }

  function toast(title, body, type = 'info') {
    const stack = $('#toast-stack');
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.innerHTML = `<div class="toast-title">${title}</div>${body ? `<div class="toast-body">${body}</div>` : ''}`;
    stack.appendChild(el);
    setTimeout(() => el.remove(), 4200);
  }

  // ---------------------------------------------------------------------
  // App open/close
  // ---------------------------------------------------------------------
  // The laptop frame itself should only be visible while the dealership
  // UI or admin console is actually open - it's a shared wrapper around
  // both, so its visibility has to reflect either one being open, not
  // just whichever one last changed.
  function updateFrameVisibility() {
    const appOpen = !$('#app').classList.contains('hidden');
    const adminOpen = !$('#admin-app').classList.contains('hidden');
    $('#frame-viewport').classList.toggle('hidden', !(appOpen || adminOpen));
  }

  function openApp(data) {
    state.ctx = data;
    $('#app').classList.remove('hidden');
    updateFrameVisibility();

    $('#dealership-name').textContent = data.dealership.label;
    $('#dealership-type').textContent = titleCase(data.dealership.type);
    $('#dealership-initial').textContent = (data.dealership.label || 'D').charAt(0);

    const perms = data.permissions || {};
    const isStaff = Object.entries(perms).some(([k, v]) => k !== 'all' && v);
    const isOwner = perms.all || perms.manage_finances || perms.configure_commissions || perms.hire;
    const canSeeDashboard = isOwner || perms.manage_loans; // Finance dept can see the financing panel without full Owner access

    const badge = $('#role-badge');
    badge.textContent = isOwner ? 'Owner' : isStaff ? 'Employee' : 'Customer';
    badge.className = 'badge' + (isOwner ? ' owner' : isStaff ? ' staff' : '');

    $('#nav-ops').classList.toggle('hidden', !isStaff);
    $('#nav-dashboard').classList.toggle('hidden', !canSeeDashboard);
    $('#nav-settings').classList.toggle('hidden', !isOwner);

    const balancePill = $('#balance-pill');
    if (isStaff) {
      balancePill.classList.remove('hidden');
      $('#balance-value').textContent = money(data.dealership.balance);
    } else {
      balancePill.classList.add('hidden');
    }

    switchView(data.initialView || 'showroom');
  }

  function hideApp() {
    $('#app').classList.add('hidden');
    $('#detail-overlay').classList.add('hidden');
    $('#modal-overlay').classList.add('hidden');
    updateFrameVisibility();
  }

  $('#btn-close').addEventListener('click', () => { nui('close'); hideApp(); });

  // ---------------------------------------------------------------------
  // View switching
  // ---------------------------------------------------------------------
  $$('.rail-btn[data-view]').forEach((btn) => {
    btn.addEventListener('click', () => switchView(btn.dataset.view));
  });

  function switchView(view) {
    state.view = view;
    $$('.rail-btn[data-view]').forEach((b) => b.classList.toggle('active', b.dataset.view === view));
    $$('.view').forEach((v) => v.classList.add('hidden'));
    $(`#view-${view}`).classList.remove('hidden');

    if (view === 'showroom') loadShowroom();
    if (view === 'ops') loadOpsInventory();
    if (view === 'dashboard') loadDashboard();
    if (view === 'settings') loadSettings();
  }

  // ---------------------------------------------------------------------
  // Showroom
  // ---------------------------------------------------------------------
  async function loadShowroom() {
    state.inventory = (await nui('getInventory')) || [];
    renderShowroom();
  }

  $('#showroom-search').addEventListener('input', renderShowroom);
  $('#showroom-sort').addEventListener('change', renderShowroom);

  function renderShowroom() {
    const q = $('#showroom-search').value.trim().toLowerCase();
    const sort = $('#showroom-sort').value;

    let list = state.inventory.filter((v) => v.model.toLowerCase().includes(q) || v.vin.toLowerCase().includes(q));
    const sorters = {
      price_asc: (a, b) => a.asking_price - b.asking_price,
      price_desc: (a, b) => b.asking_price - a.asking_price,
      mileage_asc: (a, b) => a.mileage - b.mileage,
      days_desc: (a, b) => b.days_on_lot - a.days_on_lot,
    };
    list = list.sort(sorters[sort] || sorters.price_asc);

    const grid = $('#showroom-grid');
    grid.innerHTML = '';
    $('#showroom-empty').classList.toggle('hidden', list.length > 0);

    list.forEach((v) => grid.appendChild(vehicleCard(v)));
  }

  function vehicleCard(v, opts = {}) {
    const conditions = parseConditions(v.condition_json);
    const avg = averageCondition(conditions);
    const cls = conditionClass(avg);
    const photo = getVehiclePhoto(v);

    const card = document.createElement('div');
    card.className = `vcard ${cls}`;
    card.innerHTML = `
      ${photo ? `<div class="vcard-photo"><img src="${photo}" /></div>` : ''}
      <div class="vcard-top">
        <div>
          <div class="vcard-model">${titleCase(v.model)}</div>
          <div class="vcard-category">${v.previous_owners > 0 ? v.previous_owners + ' previous owner' + (v.previous_owners > 1 ? 's' : '') : 'New'}</div>
        </div>
        <div class="vcard-price">${money(v.asking_price)}</div>
      </div>
      <div class="cbar"><div class="cbar-fill ${cls}" style="width:${avg}%"></div></div>
      <div class="vcard-meta">
        <span>${Number(v.mileage).toLocaleString()} mi</span>
        <span>${conditionLabel(avg)}</span>
        <span>${v.days_on_lot}d on lot</span>
      </div>
      <div class="vcard-vin">VIN ${v.vin}</div>
    `;
    if (!opts.static) card.addEventListener('click', () => openVehicleDetail(v.vin));
    return card;
  }

  // ---------------------------------------------------------------------
  // Vehicle detail slide-over
  // ---------------------------------------------------------------------
  async function openVehicleDetail(vin) {
    const v = await nui('getVehicle', { vin });
    if (!v) return;
    state.currentVehicle = v;
    renderVehicleDetail(v);
    $('#detail-overlay').classList.remove('hidden');
  }

  function closeDetail() { $('#detail-overlay').classList.add('hidden'); }
  $('#detail-overlay').addEventListener('click', (e) => { if (e.target.id === 'detail-overlay') closeDetail(); });

  function renderVehicleDetail(v) {
    const conditions = parseConditions(v.condition_json);
    const avg = averageCondition(conditions);
    const cls = conditionClass(avg);
    const perms = state.ctx.permissions || {};

    const partRows = Object.entries(conditions).map(([part, val]) => `
      <div class="part-row">
        <div class="part-name">${titleCase(part)}</div>
        <div class="part-bar"><div class="part-fill ${conditionClass(val)}" style="width:${val}%"></div></div>
        <div class="part-pct">${val}%</div>
      </div>
    `).join('');

    const panel = $('#detail-panel');
    const photo = getVehiclePhoto(v);
    panel.innerHTML = `
      <button class="detail-close" id="detail-close-btn"><svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg></button>
      ${photo ? `<div class="detail-photo"><img src="${photo}" /></div>` : ''}
      <div class="detail-eyebrow">${titleCase(v.acquisition_source)} &middot; ${titleCase(v.title_status)} title</div>
      <div class="detail-title">${titleCase(v.model)}</div>
      <div class="detail-vin">VIN ${v.vin}</div>

      <div class="detail-price-row">
        <div class="detail-price">${money(v.asking_price)}</div>
        <div class="detail-price-sub">${conditionLabel(avg)} condition &middot; ${avg}%</div>
      </div>

      <div class="spec-grid">
        <div class="spec"><div class="spec-label">Mileage</div><div class="spec-value">${Number(v.mileage).toLocaleString()} mi</div></div>
        <div class="spec"><div class="spec-label">Previous owners</div><div class="spec-value">${v.previous_owners}</div></div>
        <div class="spec"><div class="spec-label">Days on lot</div><div class="spec-value">${v.days_on_lot}</div></div>
        <div class="spec"><div class="spec-label">Financing</div><div class="spec-value">${v.financing_eligible ? 'Eligible' : 'Cash only'}</div></div>
      </div>

      <div class="detail-section-title">Condition report ${v.inspected ? '' : '&middot; not yet inspected'}</div>
      ${partRows || '<p style="color:var(--text-faint);font-size:12.5px;">No inspection on file yet.</p>'}

      <div class="detail-actions" id="detail-actions"></div>
    `;

    $('#detail-close-btn').addEventListener('click', closeDetail);

    const actions = $('#detail-actions');

    addAction(actions, 'Test drive', 'ghost', async () => {
      await nui('startTestDrive', { vin: v.vin });
      hideApp();
    });

    addAction(actions, 'Make an offer', 'primary', () => openNegotiationModal(v));

    if (perms.tradein_offer) {
      // trade-in is handled from its own tab; no-op button omitted here
    }
    if (perms.inspect) {
      addAction(actions, 'Run inspection', 'ghost', async () => {
        const res = await nui('inspectVehicle', { vin: v.vin });
        if (res.ok) { toast('Inspection complete', 'Condition report updated.', 'success'); openVehicleDetail(v.vin); }
        else toast('Inspection failed', res.result, 'error');
      });
    }
    if (perms.set_pricing) {
      addAction(actions, 'Adjust asking price', 'ghost', () => openAdjustPriceModal(v));
      addAction(actions, photo ? 'Retake preview photo' : 'Take preview photo', 'ghost', async () => {
        await nui('startVehiclePhoto', { vin: v.vin, model: v.model });
      });
    }
    if (perms.sell) {
      addAction(actions, 'Close sale for customer', 'ghost', () => openAssistSaleModal(v));
    }
  }

  function addAction(container, label, variant, onClick) {
    const btn = document.createElement('button');
    btn.className = `btn ${variant} block`;
    btn.textContent = label;
    btn.addEventListener('click', onClick);
    container.appendChild(btn);
  }

  // ---------------------------------------------------------------------
  // Modal helper
  // ---------------------------------------------------------------------
  function openModal({ title, body, fields = [], confirmLabel = 'Confirm', cancelLabel = 'Cancel', onConfirm }) {
    const overlay = $('#modal-overlay');
    const modal = $('#modal');

    const fieldsHtml = fields.map((f, i) => {
      if (f.type === 'select') {
        const opts = f.options.map((o) => `<option value="${o.value}" ${o.value == f.default ? 'selected' : ''}>${o.label}</option>`).join('');
        return `<div class="modal-field"><label>${f.label}</label><select data-i="${i}">${opts}</select></div>`;
      }
      if (f.type === 'color') {
        return `<div class="modal-field"><label>${f.label}</label><input data-i="${i}" type="color" value="${f.default ?? '#ffffff'}" style="height:40px;padding:2px;" /></div>`;
      }
      return `<div class="modal-field"><label>${f.label}</label><input data-i="${i}" type="${f.type || 'text'}" value="${f.default ?? ''}" ${f.min != null ? `min="${f.min}"` : ''} /></div>`;
    }).join('');

    modal.innerHTML = `
      <div class="modal-title">${title}</div>
      ${body ? `<div class="modal-body">${body}</div>` : ''}
      ${fieldsHtml}
      <div class="modal-actions">
        <button class="btn ghost" id="modal-cancel">${cancelLabel}</button>
        <button class="btn primary" id="modal-confirm">${confirmLabel}</button>
      </div>
    `;

    overlay.classList.remove('hidden');

    const close = () => overlay.classList.add('hidden');
    $('#modal-cancel').addEventListener('click', close);
    $('#modal-confirm').addEventListener('click', () => {
      const values = fields.map((f, i) => {
        const el = modal.querySelector(`[data-i="${i}"]`);
        return f.type === 'number' ? Number(el.value) : el.value;
      });
      close();
      onConfirm && onConfirm(values);
    });
  }

  // ---------------------------------------------------------------------
  // Negotiation + purchase flow
  // ---------------------------------------------------------------------
  function openNegotiationModal(v) {
    openModal({
      title: 'Make an offer',
      body: `Asking price is ${money(v.asking_price)}. What would you like to offer?`,
      fields: [{ label: 'Your offer', type: 'number', default: Math.round(v.asking_price * 0.92), min: 1 }],
      confirmLabel: 'Submit offer',
      onConfirm: async ([offer]) => {
        const result = await nui('evaluateOffer', { vin: v.vin, offer });
        if (result.verdict === 'accept') {
          openPurchaseModal(v, offer);
        } else if (result.verdict === 'counter') {
          openModal({
            title: 'Counteroffer',
            body: `The dealership counters at ${money(result.counter)}. Accept?`,
            confirmLabel: 'Accept',
            onConfirm: () => openPurchaseModal(v, result.counter),
          });
        } else {
          toast('Offer declined', 'That offer is below what this vehicle will go for.', 'error');
        }
      },
    });
  }

  function openPurchaseModal(v, finalPrice) {
    openModal({
      title: 'Finish purchase',
      body: `Agreed price: ${money(finalPrice)}. Pay in full, or finance it?`,
      fields: [
        { label: 'Down payment (0 = pay in full)', type: 'number', default: 0, min: 0 },
        { label: 'Financing term (months, ignored if paying in full)', type: 'select', default: 36, options: (state.ctx.financingTerms || [12, 24, 36, 48, 60]).map((t) => ({ value: t, label: `${t}` })) },
      ],
      confirmLabel: 'Complete purchase',
      onConfirm: async ([downPayment, termMonths]) => {
        let dealOptions = { downPayment: finalPrice, satisfactionRating: 5 };

        if (downPayment > 0 && downPayment < finalPrice) {
          const quote = await nui('quoteFinancing', { price: finalPrice, downPayment, termMonths });

          if (!quote.approved && quote.reason === 'requires_manual_review') {
            openModal({
              title: 'Submit for dealership review',
              body: "Because of a past repossession, this financing needs to be manually reviewed by dealership staff before it's approved. Submit it for review? The vehicle will be held for you while they decide.",
              confirmLabel: 'Submit request',
              onConfirm: async () => {
                const reqRes = await nui('submitFinancingRequest', { vin: v.vin, finalPrice, downPayment, termMonths });
                if (reqRes.ok) {
                  toast('Request submitted', "You'll be notified once staff make a decision.", 'success');
                  closeDetail();
                  loadShowroom();
                } else {
                  toast('Could not submit request', titleCase(reqRes.result), 'error');
                }
              },
            });
            return;
          }

          if (!quote.approved) {
            toast('Financing declined', titleCase(quote.reason), 'error');
            return;
          }
          dealOptions = {
            financed: true, downPayment, apr: quote.apr, termMonths: quote.termMonths, satisfactionRating: 5,
          };
          toast('Financing approved', `${(quote.apr * 100).toFixed(2)}% APR &middot; ${money(quote.monthlyPayment)}/mo`, 'success');
        }

        const res = await nui('kioskPurchase', { vin: v.vin, finalPrice, dealOptions });
        if (res.ok) {
          toast('Purchase complete', `Contract #${res.result.contractId} generated.`, 'success');
          closeDetail();
          loadShowroom();
        } else {
          toast('Purchase failed', titleCase(res.result), 'error');
        }
      },
    });
  }

  function openAssistSaleModal(v) {
    openModal({
      title: 'Close sale for customer',
      body: `Enter the agreed price and the customer's citizen ID. Commission is credited to you.`,
      fields: [
        { label: "Customer citizen ID", type: 'text', default: '' },
        { label: 'Agreed price', type: 'number', default: v.asking_price, min: 1 },
      ],
      confirmLabel: 'Complete sale',
      onConfirm: async ([buyerCitizenId, finalPrice]) => {
        const res = await nui('employeeSell', { vin: v.vin, buyerCitizenId, finalPrice, dealOptions: { downPayment: finalPrice, satisfactionRating: 5 } });
        if (res.ok) { toast('Sale complete', `Contract #${res.result.contractId} generated.`, 'success'); closeDetail(); loadShowroom(); }
        else toast('Sale failed', titleCase(res.result), 'error');
      },
    });
  }

  function openSendToAuctionModal(v) {
    openModal({
      title: 'Send to dealer auction',
      body: 'Other dealerships can bid on this instead of it staying in your own showroom. It leaves your in-stock list once sent.',
      fields: [
        { label: 'Starting bid', type: 'number', default: v.min_price || Math.round(v.asking_price * 0.7), min: 1 },
        { label: 'Duration (minutes)', type: 'number', default: 30, min: 5 },
      ],
      confirmLabel: 'Send to auction',
      onConfirm: async ([startingBid, durationMinutes]) => {
        const res = await nui('sendToAuction', { vin: v.vin, startingBid, durationMinutes });
        if (res.ok) { toast('Sent to auction', v.model, 'success'); loadOpsInventory(); }
        else toast('Failed', titleCase(res.result), 'error');
      },
    });
  }

  function openAdjustPriceModal(v) {
    openModal({
      title: 'Adjust asking price',
      fields: [{ label: 'New asking price', type: 'number', default: v.asking_price, min: 1 }],
      confirmLabel: 'Save',
      onConfirm: async ([price]) => {
        const res = await nui('adjustPrice', { vin: v.vin, price });
        if (res.ok) { toast('Price updated', money(price), 'success'); openVehicleDetail(v.vin); }
        else toast('Update failed', titleCase(res.result), 'error');
      },
    });
  }

  // ---------------------------------------------------------------------
  // Trade-in
  // ---------------------------------------------------------------------
  $('#btn-appraise').addEventListener('click', async () => {
    const offer = await nui('appraiseTradeIn');
    const box = $('#tradein-result');
    if (!offer || offer.error) {
      box.classList.add('hidden');
      const messages = {
        not_in_vehicle: 'Sit in the vehicle you want traded in first.',
        unknown_model: "This vehicle isn't one we can appraise - it's not a model this dealership recognizes.",
      };
      toast('Cannot appraise', messages[offer && offer.error] || 'Could not appraise that vehicle.', 'error');
      return;
    }
    state.tradeInOffer = offer;
    box.classList.remove('hidden');
    box.innerHTML = `
      <div class="tradein-row"><span class="label">Market value</span><span>${money(offer.marketValue)}</span></div>
      <div class="tradein-row"><span class="label">Offer</span><span>${money(offer.offerAmount)}</span></div>
      <button class="btn primary block" id="btn-accept-tradein" style="margin-top:10px;">Accept offer</button>
    `;
    $('#btn-accept-tradein').addEventListener('click', async () => {
      const res = await nui('acceptTradeIn', { offerId: offer.offerId });
      if (res.ok) { toast('Trade-in accepted', `You received ${money(res.result.payout)}.`, 'success'); box.classList.add('hidden'); }
      else toast('Trade-in failed', titleCase(res.result), 'error');
    });
  });

  // ---------------------------------------------------------------------
  // Dealership Ops
  // ---------------------------------------------------------------------
  $$('.subtab').forEach((tab) => {
    tab.addEventListener('click', () => {
      const group = tab.closest('.subtabs');
      group.querySelectorAll('.subtab').forEach((t) => t.classList.toggle('active', t === tab));
      $$('.subview').forEach((v) => v.classList.add('hidden'));
      $('#' + tab.dataset.subtab).classList.remove('hidden');
      if (tab.dataset.subtab === 'ops-order') { renderCatalog(); loadPendingOrders(); }
      if (tab.dataset.subtab === 'ops-auctions') loadAuctions();
      if (tab.dataset.subtab === 'ops-staff') loadStaff();
      if (tab.dataset.subtab === 'ops-display') loadDisplaySlots();
      if (tab.dataset.subtab === 'ops-trade') loadTrade();
      if (tab.dataset.subtab === 'admin-catalog') loadCatalogAdmin();
      if (tab.dataset.subtab === 'set-branding') loadBranding();
      if (tab.dataset.subtab === 'set-zones') loadZones();
      if (tab.dataset.subtab === 'set-lighting') loadLights();
    });
  });

  async function loadOpsInventory() {
    const inv = (await nui('getInventory')) || [];
    state.inventory = inv;
    const perms = state.ctx.permissions || {};
    const tbody = $('#ops-inventory-table tbody');
    tbody.innerHTML = '';

    inv.forEach((v) => {
      const conditions = parseConditions(v.condition_json);
      const avg = averageCondition(conditions);
      const photo = getVehiclePhoto(v);
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${photo ? `<img src="${photo}" style="width:40px;height:28px;object-fit:cover;border-radius:4px;vertical-align:middle;margin-right:8px;" />` : ''}${titleCase(v.model)}</td>
        <td class="mono">${v.vin}</td>
        <td>${Number(v.mileage).toLocaleString()} mi</td>
        <td>${avg}%</td>
        <td>${v.days_on_lot}</td>
        <td>${money(v.asking_price)}</td>
        <td class="row-actions"></td>
      `;
      const actions = tr.querySelector('.row-actions');
      if (perms.inspect) actions.appendChild(smallBtn('Inspect', async () => {
        const res = await nui('inspectVehicle', { vin: v.vin });
        if (res.ok) { toast('Inspected', v.vin, 'success'); loadOpsInventory(); } else toast('Failed', res.result, 'error');
      }));
      if (perms.set_pricing) actions.appendChild(smallBtn('Price', () => openAdjustPriceModal(v)));
      if (perms.set_pricing) actions.appendChild(smallBtn(photo ? 'Retake photo' : 'Take photo', async () => {
        await nui('startVehiclePhoto', { vin: v.vin, model: v.model });
      }));
      if (perms.purchase_inventory) actions.appendChild(smallBtn('Send to auction', () => openSendToAuctionModal(v)));
      if (perms.sell) actions.appendChild(smallBtn('Sell', () => openAssistSaleModal(v)));
      tbody.appendChild(tr);
    });
  }

  function smallBtn(label, onClick) {
    const b = document.createElement('button');
    b.className = 'btn ghost small';
    b.textContent = label;
    b.addEventListener('click', onClick);
    return b;
  }

  function renderCatalog() {
    const grid = $('#catalog-grid');
    grid.innerHTML = '';
    (state.ctx.catalog || []).forEach((entry) => {
      const card = document.createElement('div');
      card.className = 'vcard';
      card.innerHTML = `
        <div class="vcard-top">
          <div>
            <div class="vcard-model">${entry.label}</div>
            <div class="vcard-category">${titleCase(entry.category)} &middot; ${titleCase(entry.rarity)}</div>
          </div>
          <div class="vcard-price">${money(entry.msrp)}</div>
        </div>
      `;
      const btn = document.createElement('button');
      btn.className = 'btn primary block';
      btn.style.marginTop = '12px';
      btn.textContent = 'Order from factory';
      btn.addEventListener('click', async () => {
        const res = await nui('submitFactoryOrder', { model: entry.model });
        if (res.ok) { toast('Order placed', `${entry.label} charged - head to the truck spawn to start the delivery run.`, 'success'); loadPendingOrders(); }
        else toast('Order failed', titleCase(res.result), 'error');
      });
      card.appendChild(btn);
      grid.appendChild(card);
    });
  }

  async function loadPendingOrders() {
    const el = $('#pending-orders-list');
    if (!el) return;
    const orders = (await nui('getPendingOrders')) || [];
    if (!orders.length) {
      el.innerHTML = '<p style="color:var(--text-faint);font-size:13px;">No orders in progress.</p>';
      return;
    }
    el.innerHTML = orders.map((o) => `
      <div class="intel-row"><span>${titleCase(o.model)}</span><span class="intel-tag ${o.status === 'picking_up' ? 'up' : ''}">${o.status === 'picking_up' ? 'Out for pickup' : 'Awaiting pickup'}</span></div>
    `).join('');
  }

  async function loadAuctions() {
    const auctions = (await nui('getOpenAuctions')) || [];
    const grid = $('#auctions-grid');
    grid.innerHTML = '';
    if (!auctions.length) {
      grid.innerHTML = '<p style="color:var(--text-faint);font-size:13px;">No open auctions right now.</p>';
      return;
    }
    auctions.forEach((a) => {
      const card = document.createElement('div');
      card.className = 'vcard';
      card.innerHTML = `
        <div class="vcard-top">
          <div>
            <div class="vcard-model">${titleCase(a.model)}</div>
            <div class="vcard-category">${titleCase(a.source_type)} &middot; ${Number(a.mileage).toLocaleString()} mi</div>
          </div>
          <div class="vcard-price">${money(a.current_bid)}</div>
        </div>
        <div class="vcard-meta"><span>Current bidder: ${a.current_bidder || 'none'}</span></div>
      `;
      const row = document.createElement('div');
      row.style.display = 'flex'; row.style.gap = '8px'; row.style.marginTop = '10px';
      const input = document.createElement('input');
      input.className = 'num-input'; input.type = 'number'; input.style.flex = '1';
      input.placeholder = `> ${money(a.current_bid)}`;
      const bidBtn = document.createElement('button');
      bidBtn.className = 'btn primary small'; bidBtn.textContent = 'Bid';
      bidBtn.addEventListener('click', async () => {
        const amount = Number(input.value);
        const res = await nui('placeBid', { auctionId: a.id, amount });
        if (res.ok) { toast('Bid placed', money(amount), 'success'); loadAuctions(); }
        else toast('Bid failed', titleCase(res.result), 'error');
      });
      row.appendChild(input); row.appendChild(bidBtn);
      card.appendChild(row);
      grid.appendChild(card);
    });
  }

  // ---------------------------------------------------------------------
  // Staff (hire/fire)
  // ---------------------------------------------------------------------
  let staffGradeSelectInited = false;

  async function loadStaff() {
    if (!staffGradeSelectInited) {
      $('#hire-grade').innerHTML = (state.ctx.staffGrades || []).map((g) => `<option value="${g.level}">${g.label}</option>`).join('');
      staffGradeSelectInited = true;
    }

    const staff = (await nui('getOnlineStaff')) || [];
    const tbody = $('#staff-table tbody');
    tbody.innerHTML = '';

    if (!staff.length) {
      tbody.innerHTML = '<tr><td colspan="3" style="color:var(--text-faint);">No staff currently online.</td></tr>';
      return;
    }

    staff.forEach((s) => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${s.name} <span class="mono">(#${s.id})</span></td>
        <td>${s.gradeName} (grade ${s.grade})</td>
        <td class="row-actions"></td>
      `;
      tr.querySelector('.row-actions').appendChild(smallBtn('Fire', async () => {
        const res = await nui('fireStaff', { targetId: s.id });
        if (res.ok) { toast('Fired', s.name, 'success'); loadStaff(); }
        else toast('Failed', titleCase(res.result), 'error');
      }));
      tbody.appendChild(tr);
    });
  }

  $('#btn-hire').addEventListener('click', async () => {
    const targetId = Number($('#hire-player-id').value);
    const grade = Number($('#hire-grade').value);
    if (!targetId) { toast('Hire', 'Enter a player ID.', 'error'); return; }

    const res = await nui('hireStaff', { targetId, grade });
    if (res.ok) { toast('Hired', `Player #${targetId} is now grade ${grade}.`, 'success'); $('#hire-player-id').value = ''; loadStaff(); }
    else toast('Hire failed', titleCase(res.result), 'error');
  });

  // ---------------------------------------------------------------------
  // Vehicle display slots
  // ---------------------------------------------------------------------
  async function loadDisplaySlots() {
    const [slots, inventory] = await Promise.all([nui('getDisplayZones'), nui('getInventory')]);
    const tbody = $('#display-table tbody');
    tbody.innerHTML = '';

    if (!slots.length) {
      tbody.innerHTML = '<tr><td colspan="3" style="color:var(--text-faint);">No vehicle display slots placed yet - add one in Settings &gt; Zones.</td></tr>';
      return;
    }

    slots.forEach((slot) => {
      const tr = document.createElement('tr');
      const assignedText = slot.assignment ? `${titleCase(slot.assignment.model)} (${slot.assignment.vin})` : '<span style="color:var(--text-faint);">Empty</span>';
      tr.innerHTML = `
        <td>${slot.label || `Slot #${slot.id}`}</td>
        <td>${assignedText}</td>
        <td class="row-actions"></td>
      `;
      const actions = tr.querySelector('.row-actions');
      actions.appendChild(smallBtn('Assign', () => openAssignDisplayModal(slot, inventory)));
      if (slot.assignment) {
        actions.appendChild(smallBtn('Clear', async () => {
          const res = await nui('clearDisplayVehicle', { zoneId: slot.id });
          if (res.ok) { toast('Slot cleared', slot.label || `Slot #${slot.id}`, 'success'); loadDisplaySlots(); }
          else toast('Failed', titleCase(res.result), 'error');
        }));
      }
      tbody.appendChild(tr);
    });
  }

  // ---------------------------------------------------------------------
  // Dealer-to-dealer trading
  // ---------------------------------------------------------------------
  $('#btn-submit-transfer').addEventListener('click', async () => {
    const vin = $('#trade-vin').value;
    const toDealership = $('#trade-target').value;
    const cashAdjustment = Number($('#trade-cash').value) || 0;
    if (!vin || !toDealership) { toast('Missing info', 'Pick a vehicle and a target dealership.', 'error'); return; }

    const res = await nui('submitTransferOffer', { vin, toDealership, cashAdjustment });
    if (res.ok) { toast('Offer sent', 'Waiting on the other dealership.', 'success'); loadTrade(); }
    else toast('Failed', titleCase(res.result), 'error');
  });

  async function loadTrade() {
    const [inventory, targets, incoming, outgoing] = await Promise.all([
      nui('getInventory'), nui('getAllDealershipNames'), nui('getIncomingTransfers'), nui('getOutgoingTransfers'),
    ]);

    dealershipNameCache = { [state.ctx.dealership.name]: state.ctx.dealership.label };
    (targets || []).forEach((d) => { dealershipNameCache[d.name] = d.label; });

    const vinSelect = $('#trade-vin');
    vinSelect.innerHTML = (inventory || []).map((v) => `<option value="${v.vin}">${titleCase(v.model)} - ${money(v.asking_price)} (${v.vin})</option>`).join('')
      || '<option value="">Nothing in stock</option>';

    const targetSelect = $('#trade-target');
    targetSelect.innerHTML = (targets || []).map((d) => `<option value="${d.name}">${d.label}</option>`).join('')
      || '<option value="">No other dealerships yet</option>';

    renderIncomingTransfers(incoming || []);
    renderOutgoingTransfers(outgoing || []);
  }

  function renderIncomingTransfers(rows) {
    const tbody = $('#incoming-transfers-table tbody');
    tbody.innerHTML = '';
    if (!rows.length) {
      tbody.innerHTML = '<tr><td colspan="4" style="color:var(--text-faint);">No incoming offers.</td></tr>';
      return;
    }
    rows.forEach((r) => {
      const fromLabel = dealershipNameCache[r.from_dealership] || r.from_dealership;
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${fromLabel}</td>
        <td>${titleCase(r.model || r.vin)} <span class="mono">(${r.vin})</span></td>
        <td>${money(r.cash_adjustment)}</td>
        <td class="row-actions"></td>
      `;
      const actions = tr.querySelector('.row-actions');
      actions.appendChild(smallBtn('Accept', async () => {
        const res = await nui('acceptTransferOffer', { transferId: r.id });
        if (res.ok) { toast('Transfer accepted', r.vin, 'success'); loadTrade(); }
        else toast('Failed', titleCase(res.result), 'error');
      }));
      const declineBtn = smallBtn('Decline', async () => {
        const res = await nui('declineTransferOffer', { transferId: r.id });
        if (res.ok) { toast('Transfer declined', r.vin, 'success'); loadTrade(); }
        else toast('Failed', titleCase(res.result), 'error');
      });
      declineBtn.classList.add('danger');
      declineBtn.classList.remove('ghost');
      actions.appendChild(declineBtn);
      tbody.appendChild(tr);
    });
  }

  function renderOutgoingTransfers(rows) {
    const tbody = $('#outgoing-transfers-table tbody');
    tbody.innerHTML = '';
    if (!rows.length) {
      tbody.innerHTML = '<tr><td colspan="4" style="color:var(--text-faint);">No outgoing offers.</td></tr>';
      return;
    }
    rows.forEach((r) => {
      const toLabel = dealershipNameCache[r.to_dealership] || r.to_dealership;
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${toLabel}</td>
        <td>${titleCase(r.model || r.vin)} <span class="mono">(${r.vin})</span></td>
        <td>${money(r.cash_adjustment)}</td>
        <td class="row-actions"></td>
      `;
      const cancelBtn = smallBtn('Cancel', async () => {
        const res = await nui('cancelTransferOffer', { transferId: r.id });
        if (res.ok) { toast('Offer cancelled', r.vin, 'success'); loadTrade(); }
        else toast('Failed', titleCase(res.result), 'error');
      });
      cancelBtn.classList.add('danger');
      cancelBtn.classList.remove('ghost');
      tr.querySelector('.row-actions').appendChild(cancelBtn);
      tbody.appendChild(tr);
    });
  }

  function openAssignDisplayModal(slot, inventory) {
    if (!inventory.length) {
      toast('No inventory', 'Nothing in stock to assign right now.', 'error');
      return;
    }
    openModal({
      title: `Assign vehicle - ${slot.label || `Slot #${slot.id}`}`,
      fields: [{
        label: 'Vehicle', type: 'select',
        options: inventory.map((v) => ({ value: v.vin, label: `${titleCase(v.model)} - ${money(v.asking_price)} (${v.vin})` })),
      }],
      confirmLabel: 'Assign',
      onConfirm: async ([vin]) => {
        const res = await nui('assignDisplayVehicle', { zoneId: slot.id, vin });
        if (res.ok) { toast('Vehicle assigned', slot.label || `Slot #${slot.id}`, 'success'); loadDisplaySlots(); }
        else toast('Failed', titleCase(res.result), 'error');
      },
    });
  }

  // ---------------------------------------------------------------------
  // Dashboard
  // ---------------------------------------------------------------------
  async function loadDashboard() {
    $('#balance-value').textContent = money(state.ctx.dealership.balance);

    const intel = await nui('getMarketIntel');
    renderIntel(intel);

    const aging = (await nui('getAgingReport')) || [];
    renderAging(aging);

    const leaderboard = (await nui('getLeaderboard')) || [];
    renderLeaderboard(leaderboard);

    const rep = await nui('getReputation');
    renderReputation(rep);

    await refreshFinancing();
    await refreshFinancingRequests();
    startRepoTrackingPoll();
  }

  let currentLoans = [];
  let repoTrackingTimer = null;

  async function refreshFinancing() {
    currentLoans = (await nui('getActiveLoans')) || [];
    const tracking = (await nui('getRepoTracking')) || {};
    renderFinancing(currentLoans, tracking);
  }

  // Polls just the live-location cache (cheap) every 15s while the
  // Dashboard is actually open, so repo rows update without needing to
  // reload the whole panel - stops itself once the app closes or you
  // navigate elsewhere, so it's not running in the background forever.
  function startRepoTrackingPoll() {
    if (repoTrackingTimer) clearInterval(repoTrackingTimer);
    repoTrackingTimer = setInterval(async () => {
      if ($('#app').classList.contains('hidden') || state.view !== 'dashboard') {
        clearInterval(repoTrackingTimer);
        repoTrackingTimer = null;
        return;
      }
      const tracking = (await nui('getRepoTracking')) || {};
      renderFinancing(currentLoans, tracking);
    }, 15000);
  }

  function renderFinancing(loans, tracking = {}) {
    const tbody = $('#financing-table tbody');
    tbody.innerHTML = '';

    if (!loans.length) {
      tbody.innerHTML = '<tr><td colspan="8" style="color:var(--text-faint);">No active financing contracts.</td></tr>';
      return;
    }

    loans.forEach((l) => {
      const dueDate = new Date(l.next_due_at).toLocaleString();
      const isDefaulted = l.status === 'defaulted';
      const track = tracking[String(l.id)];
      const statusText = isDefaulted
        ? (track ? `Repo-eligible &middot; last seen ${Math.round(track.ageMs / 1000)}s ago` : 'Repo-eligible &middot; not currently out of garage')
        : (l.missed_at ? 'Payment missed' : 'Current');

      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="mono">${l.citizenid}</td>
        <td>${titleCase(l.model || l.vin)} <span class="mono">(${l.vin})</span></td>
        <td>${money(l.balance)}</td>
        <td>${money(l.monthly_payment)}</td>
        <td>${dueDate}</td>
        <td>${l.missed_payments}</td>
        <td><span class="source-tag ${isDefaulted ? 'config' : (l.missed_at ? 'config' : 'registry')}">${statusText}</span></td>
        <td class="row-actions"></td>
      `;
      const actions = tr.querySelector('.row-actions');
      actions.appendChild(smallBtn('Ping location', async () => {
        const res = await nui('pingFinancedVehicle', { loanId: l.id });
        if (res.ok) toast('Located', 'Waypoint set to its last known position.', 'success');
        else toast('Not found', "That vehicle isn't currently loaded anywhere - likely in a garage or just not streamed in.", 'error');
      }));
      if (isDefaulted) {
        const recoverBtn = smallBtn('Mark recovered', () => openMarkRecoveredModal(l));
        recoverBtn.classList.add('danger');
        recoverBtn.classList.remove('ghost');
        actions.appendChild(recoverBtn);
      }
      tbody.appendChild(tr);
    });
  }

  function openMarkRecoveredModal(l) {
    openModal({
      title: 'Mark this vehicle recovered?',
      body: `Confirms VIN ${l.vin} has physically been recovered. This closes the contract, returns it to your inventory, and flags the customer for manual financing review on any future request.`,
      confirmLabel: 'Mark recovered',
      onConfirm: async () => {
        const res = await nui('completeRepo', { loanId: l.id });
        if (res.ok) { toast('Vehicle recovered', l.vin, 'success'); refreshFinancing(); }
        else toast('Failed', titleCase(res.result), 'error');
      },
    });
  }

  // ---------------------------------------------------------------------
  // Financing requests (flagged customers - manual approve/deny)
  // ---------------------------------------------------------------------
  async function refreshFinancingRequests() {
    const requests = (await nui('getFinancingRequests')) || [];
    renderFinancingRequests(requests);
  }

  function renderFinancingRequests(requests) {
    const tbody = $('#financing-requests-table tbody');
    tbody.innerHTML = '';

    if (!requests.length) {
      tbody.innerHTML = '<tr><td colspan="6" style="color:var(--text-faint);">No pending financing requests.</td></tr>';
      return;
    }

    requests.forEach((r) => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="mono">${r.citizenid}</td>
        <td>${titleCase(r.model || r.vin)} <span class="mono">(${r.vin})</span></td>
        <td>${money(r.sale_price)}</td>
        <td>${money(r.down_payment)}</td>
        <td>${r.term_months}mo &middot; ${(Number(r.apr) * 100).toFixed(2)}% APR</td>
        <td class="row-actions"></td>
      `;
      const actions = tr.querySelector('.row-actions');
      actions.appendChild(smallBtn('Approve', async () => {
        const res = await nui('approveFinancingRequest', { requestId: r.id });
        if (res.ok) { toast('Request approved', r.vin, 'success'); refreshFinancingRequests(); refreshFinancing(); }
        else toast('Failed', titleCase(res.result), 'error');
      }));
      const denyBtn = smallBtn('Deny', async () => {
        const res = await nui('denyFinancingRequest', { requestId: r.id });
        if (res.ok) { toast('Request denied', r.vin, 'success'); refreshFinancingRequests(); }
        else toast('Failed', titleCase(res.result), 'error');
      });
      denyBtn.classList.add('danger');
      denyBtn.classList.remove('ghost');
      actions.appendChild(denyBtn);
      tbody.appendChild(tr);
    });
  }

  function renderIntel(intel) {
    const el = $('#dash-intel');
    if (!intel) { el.innerHTML = ''; return; }
    const section = (title, arr, tagClass, valueKey) => `
      <div class="intel-row"><span class="intel-label">${title}</span></div>
      ${arr.length ? arr.map((v) => `<div class="intel-row"><span>${v.label}</span><span class="intel-tag ${tagClass}">${v[valueKey]}</span></div>`).join('') : '<div class="intel-row"><span class="intel-label">None</span></div>'}
    `;
    el.innerHTML = section('Trending', intel.trending, 'up', 'unitsSold')
      + section('Low supply', intel.lowSupply, 'up', 'unitsListed')
      + section('Oversupply', intel.oversupply, 'down', 'unitsListed');
  }

  function renderAging(rows) {
    const el = $('#dash-aging');
    if (!rows.length) { el.innerHTML = '<p style="color:var(--text-faint);font-size:13px;">Nothing aging right now.</p>'; return; }
    el.innerHTML = rows.map((r) => `
      <div class="intel-row"><span>${titleCase(r.model)} &middot; ${r.vin}</span><span>${r.days_on_lot}d</span></div>
    `).join('');
  }

  function renderLeaderboard(rows) {
    const el = $('#dash-leaderboard');
    if (!rows.length) { el.innerHTML = '<p style="color:var(--text-faint);font-size:13px;">No sales recorded yet.</p>'; return; }
    el.innerHTML = rows.map((r, i) => `
      <div class="lb-row">
        <div class="lb-rank">${i + 1}</div>
        <div class="lb-name">${r.citizenid}</div>
        <div class="lb-stat">${r.vehicles_sold} sold</div>
        <div class="lb-stat">${money(r.sales_volume)}</div>
      </div>
    `).join('');
  }

  function renderReputation(rep) {
    const el = $('#dash-reputation');
    if (!rep) { el.innerHTML = ''; return; }
    const fields = [
      ['overall', 'Overall'], ['customer_service', 'Customer service'], ['pricing', 'Pricing'],
      ['honesty', 'Honesty'], ['vehicle_quality', 'Vehicle quality'], ['financing_rep', 'Financing'],
      ['sales_experience', 'Sales experience'], ['after_sales_support', 'After-sales support'],
    ];
    el.innerHTML = fields.map(([key, label]) => `
      <div class="rep-row">
        <div class="rep-label">${label}</div>
        <div class="rep-bar"><div class="rep-fill" style="width:${rep[key]}%"></div></div>
        <div class="rep-value">${Math.round(rep[key])}</div>
      </div>
    `).join('');
  }

  $('#btn-clearance').addEventListener('click', async () => {
    const days = Number($('#clearance-days').value);
    const percent = Number($('#clearance-percent').value);
    const ok = await nui('clearanceSale', { days, percent });
    if (ok) { toast('Clearance sale applied', `${percent}% off vehicles ${days}+ days on lot.`, 'success'); loadDashboard(); }
    else toast('Failed', 'Could not apply clearance sale.', 'error');
  });

  // ---------------------------------------------------------------------
  // Settings: branding
  // ---------------------------------------------------------------------
  let settingsInited = false;

  function loadSettings() {
    if (!settingsInited) {
      initSettingsSelectors();
      settingsInited = true;
    }
    loadBranding();
  }

  function initSettingsSelectors() {
    const zoneSelect = $('#zone-type-select');
    zoneSelect.innerHTML = (state.ctx.zoneTypes || []).map((z) => `<option value="${z.key}">${z.label}</option>`).join('');

    const lightSelect = $('#light-type-select');
    lightSelect.innerHTML = (state.ctx.lightTypes || []).map((l) => `<option value="${l.key}">${l.label}</option>`).join('');
  }

  async function loadBranding() {
    const b = await nui('getBranding');
    if (!b) return;
    $('#brand-name').value = b.label;
    $('#brand-sprite').value = b.blipSprite;
    $('#brand-color').value = b.blipColor;
    $('#brand-scale').value = b.blipScale;
  }

  $('#btn-save-branding').addEventListener('click', async () => {
    const branding = {
      label: $('#brand-name').value,
      blipSprite: Number($('#brand-sprite').value),
      blipColor: Number($('#brand-color').value),
      blipScale: Number($('#brand-scale').value),
    };
    const res = await nui('updateBranding', { branding });
    if (res.ok) {
      toast('Branding updated', branding.label, 'success');
      $('#dealership-name').textContent = branding.label;
      $('#dealership-initial').textContent = branding.label.charAt(0);
    } else {
      toast('Update failed', titleCase(res.result), 'error');
    }
  });

  // ---------------------------------------------------------------------
  // Settings: zones
  // ---------------------------------------------------------------------
  function zoneTypeDef(key) {
    return (state.ctx.zoneTypes || []).find((z) => z.key === key) || { label: key, shape: 'point' };
  }

  async function loadZones() {
    const zones = (await nui('getZones')) || [];
    const tbody = $('#zones-table-body');
    tbody.innerHTML = '';
    zones.forEach((z) => {
      const def = zoneTypeDef(z.zone_type);
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${def.label}</td>
        <td>${z.label || '-'}</td>
        <td>${z.shape}${def.interactable ? ` &middot; ${z.interaction === 'press_e' ? 'Press E' : 'Target'}` : ''}</td>
        <td class="mono">${z.pos_x.toFixed(1)}, ${z.pos_y.toFixed(1)}, ${z.pos_z.toFixed(1)}</td>
        <td class="row-actions"></td>
      `;
      tr.querySelector('.row-actions').appendChild(smallBtn('Delete', async () => {
        const res = await nui('deleteZone', { id: z.id });
        if (res.ok) { toast('Zone removed', def.label, 'success'); loadZones(); }
        else toast('Failed', titleCase(res.result), 'error');
      }));
      tbody.appendChild(tr);
    });
  }

  $('#btn-add-zone').addEventListener('click', async () => {
    const zoneType = $('#zone-type-select').value;
    const def = zoneTypeDef(zoneType);
    if (def.shape === 'poly') await nui('startPolygonCapture', { zoneType });
    else await nui('startZoneCapture', { zoneType });
  });

  function finishZoneCreation(zoneType, placement) {
    const def = zoneTypeDef(zoneType);
    const fields = [{ label: 'Label', type: 'text', default: def.label }];
    if (def.interactable) {
      fields.push({
        label: 'Interaction', type: 'select', default: 'target',
        options: [{ value: 'target', label: 'Target (ox_target prompt)' }, { value: 'press_e', label: 'Press E nearby' }],
      });
    }

    openModal({
      title: `Save ${def.label.toLowerCase()}`,
      body: def.shape === 'poly' ? `${placement.points.length}-corner area captured. Name it and confirm.` : 'Position captured. Name it and confirm.',
      fields,
      confirmLabel: 'Save zone',
      onConfirm: async (values) => {
        const [label, interaction] = values;
        const zone = {
          zoneType, shape: def.shape, label, heading: placement.heading,
          interaction: def.interactable ? interaction : undefined,
          pos: def.shape === 'poly' ? undefined : placement.pos,
          points: def.shape === 'poly' ? placement.points : undefined,
        };
        const res = await nui('createZone', { zone });
        if (res.ok) { toast('Zone saved', label, 'success'); loadZones(); }
        else toast('Save failed', titleCase(res.result), 'error');
      },
    });
  }

  // ---------------------------------------------------------------------
  // Settings: lighting
  // ---------------------------------------------------------------------
  function lightTypeDef(key) {
    return (state.ctx.lightTypes || []).find((l) => l.key === key) || { label: key, hasDirection: false, defaultRange: 10, defaultBrightness: 5, defaultRadius: 5 };
  }

  function rgbToHex(r, g, b) {
    return '#' + [r, g, b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');
  }
  function hexToRgb(hex) {
    const n = parseInt(hex.replace('#', ''), 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
  }

  // Rebuilds a full updateLight payload from an existing DB row, applying
  // `overrides` on top - used by quick actions (like the on/off toggle)
  // that only mean to change one field but the server expects all of them.
  function lightPayloadFrom(l, overrides = {}) {
    return Object.assign({
      label: l.label,
      pos: { x: l.pos_x, y: l.pos_y, z: l.pos_z },
      dir: { x: l.dir_x, y: l.dir_y, z: l.dir_z },
      color: { r: l.color_r, g: l.color_g, b: l.color_b },
      brightness: l.brightness, range: l.range, radius: l.radius,
      falloff: l.falloff, shadow: !!l.shadow, enabled: l.enabled === 1 || l.enabled === true,
    }, overrides);
  }

  async function loadLights() {
    const lights = (await nui('getLights')) || [];
    state.lights = lights;
    const tbody = $('#lights-table-body');
    tbody.innerHTML = '';
    lights.forEach((l) => {
      const def = lightTypeDef(l.type);
      const isOn = l.enabled === 1 || l.enabled === true;
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${def.label}</td>
        <td>${l.label || '-'}</td>
        <td><span style="display:inline-block;width:14px;height:14px;border-radius:3px;background:${rgbToHex(l.color_r, l.color_g, l.color_b)};border:1px solid var(--border-bright);"></span></td>
        <td>${l.brightness}</td>
        <td>${l.range}m</td>
        <td><span class="source-tag ${isOn ? 'registry' : 'config'}">${isOn ? 'On' : 'Off'}</span></td>
        <td class="row-actions"></td>
      `;
      const actions = tr.querySelector('.row-actions');
      actions.appendChild(smallBtn(isOn ? 'Turn off' : 'Turn on', async () => {
        const light = lightPayloadFrom(l, { enabled: !isOn });
        const res = await nui('updateLight', { id: l.id, light });
        if (res.ok) { toast(isOn ? 'Light turned off' : 'Light turned on', def.label, 'success'); loadLights(); }
        else toast('Failed', titleCase(res.result), 'error');
      }));
      actions.appendChild(smallBtn('Locate', async () => {
        await nui('locateLight', { id: l.id });
        toast('Locating', `${def.label} highlighted for 6s - look around nearby.`, 'success');
      }));
      actions.appendChild(smallBtn('Edit', () => openLightEditModal(l)));
      actions.appendChild(smallBtn('Reposition', async () => {
        await nui('startLightPlacement', { mode: 'edit', lightType: l.type, lightId: l.id });
      }));
      actions.appendChild(smallBtn('Delete', async () => {
        const res = await nui('deleteLight', { id: l.id });
        if (res.ok) { toast('Light removed', def.label, 'success'); loadLights(); }
        else toast('Failed', titleCase(res.result), 'error');
      }));
      tbody.appendChild(tr);
    });
  }

  $('#btn-add-light').addEventListener('click', async () => {
    const lightType = $('#light-type-select').value;
    await nui('startLightPlacement', { mode: 'create', lightType });
  });

  function finishLightCreation(lightType, placement) {
    const def = lightTypeDef(lightType);
    openModal({
      title: `Configure ${def.label.toLowerCase()}`,
      body: 'Position captured. Set its look and confirm.',
      fields: [
        { label: 'Label', type: 'text', default: def.label },
        { label: 'Color', type: 'color', default: '#ffe6b3' },
        { label: 'Brightness', type: 'number', default: def.defaultBrightness, min: 0.1 },
        { label: 'Range', type: 'number', default: def.defaultRange, min: 1 },
        { label: 'Radius (cone size)', type: 'number', default: def.defaultRadius, min: 1 },
        { label: 'Cast shadow', type: 'select', default: 0, options: [{ value: 0, label: 'No' }, { value: 1, label: 'Yes' }] },
      ],
      confirmLabel: 'Save light',
      onConfirm: async ([label, color, brightness, range, radius, shadow]) => {
        const rgb = hexToRgb(color);
        const light = {
          type: lightType, label, pos: placement.pos, dir: placement.dir,
          color: rgb, brightness, range, radius, falloff: 100, shadow: Number(shadow) === 1,
        };
        const res = await nui('createLight', { light });
        if (res.ok) { toast('Light saved', label, 'success'); loadLights(); }
        else toast('Save failed', titleCase(res.result), 'error');
      },
    });
  }

  function openLightEditModal(l) {
    const def = lightTypeDef(l.type);
    openModal({
      title: `Edit ${def.label.toLowerCase()}`,
      fields: [
        { label: 'Label', type: 'text', default: l.label || def.label },
        { label: 'Color', type: 'color', default: rgbToHex(l.color_r, l.color_g, l.color_b) },
        { label: 'Brightness', type: 'number', default: l.brightness, min: 0.1 },
        { label: 'Range', type: 'number', default: l.range, min: 1 },
        { label: 'Radius (cone size)', type: 'number', default: l.radius, min: 1 },
        { label: 'Cast shadow', type: 'select', default: l.shadow, options: [{ value: 0, label: 'No' }, { value: 1, label: 'Yes' }] },
      ],
      confirmLabel: 'Save changes',
      onConfirm: async ([label, color, brightness, range, radius, shadow]) => {
        const rgb = hexToRgb(color);
        const light = {
          label, pos: { x: l.pos_x, y: l.pos_y, z: l.pos_z }, dir: { x: l.dir_x, y: l.dir_y, z: l.dir_z },
          color: rgb, brightness, range, radius, falloff: l.falloff, shadow: Number(shadow) === 1, enabled: true,
        };
        const res = await nui('updateLight', { id: l.id, light });
        if (res.ok) { toast('Light updated', label, 'success'); loadLights(); }
        else toast('Update failed', titleCase(res.result), 'error');
      },
    });
  }

  // ---------------------------------------------------------------------
  // Placement tool result handoff (light/zone in-world capture)
  // ---------------------------------------------------------------------
  function handlePlacementResult(data) {
    // Showing the interface again comes FIRST and is never allowed to be
    // skipped. Lua has already handed focus back by the time this runs, so
    // anything that throws in here would otherwise leave the player with a
    // mouse cursor and a blank screen.
    $('#app').classList.remove('hidden');
    updateFrameVisibility();

    if (!state.ctx) {
      // No dealership context (page reloaded mid-placement, or a result
      // arrived for a session that's gone). Nothing sensible to show.
      nui('close');
      hideApp();
      return;
    }

    try {
      applyPlacementResult(data);
    } catch (e) {
      console.error('[st_dealership] placement result failed:', e);
      toast('Placement failed', 'The capture could not be applied - the menu is still open.', 'error');
    }
  }

  function applyPlacementResult(data) {
    if (!data) return;

    switchView('settings');

    const group = document.querySelector('#view-settings .subtabs');
    const targetSubtab = data.kind === 'light' ? 'set-lighting' : 'set-zones';
    group.querySelectorAll('.subtab').forEach((t) => t.classList.toggle('active', t.dataset.subtab === targetSubtab));
    $$('.subview').forEach((v) => v.classList.add('hidden'));
    $('#' + targetSubtab).classList.remove('hidden');

    if (!data.placement) return; // cancelled

    if (data.kind === 'light') {
      if (data.mode === 'edit') {
        repositionLight(data.lightId, data.placement);
      } else {
        finishLightCreation(data.lightType, data.placement);
      }
    } else if (data.kind === 'zone') {
      finishZoneCreation(data.zoneType, data.placement);
    }
  }

  async function repositionLight(id, placement) {
    const existing = (state.lights || []).find((l) => l.id === id);
    if (!existing) { loadLights(); return; }
    const light = {
      label: existing.label, pos: placement.pos, dir: placement.dir,
      color: { r: existing.color_r, g: existing.color_g, b: existing.color_b },
      brightness: existing.brightness, range: existing.range, radius: existing.radius,
      falloff: existing.falloff, shadow: !!existing.shadow, enabled: true,
    };
    const res = await nui('updateLight', { id, light });
    if (res.ok) { toast('Light repositioned', existing.label, 'success'); loadLights(); }
    else toast('Failed', titleCase(res.result), 'error');
  }

  // ---------------------------------------------------------------------
  // Admin console (/admindealership) - separate from the per-dealership
  // app above; opens independently and lists every dealership on the
  // server, config-defined and runtime-created alike.
  // ---------------------------------------------------------------------
  let adminDealerships = [];
  let adminCatalog = [];
  let adminCategories = ['sedan'];
  let adminRarities = ['common', 'uncommon', 'rare', 'exotic'];
  let adminMyPlayerId = null;

  function openAdmin(data) {
    adminDealerships = data.dealerships || [];
    adminCatalog = data.catalog || [];
    adminCategories = data.categories || ['sedan'];
    adminRarities = data.rarities || ['common', 'uncommon', 'rare', 'exotic'];
    adminMyPlayerId = data.myPlayerId || null;
    if (!state.ctx) state.ctx = { currencySymbol: data.currencySymbol || '$' };
    $('#admin-app').classList.remove('hidden');
    updateFrameVisibility();
    renderAdminTable();
  }

  function hideAdmin() {
    $('#admin-app').classList.add('hidden');
    $('#detail-overlay').classList.add('hidden');
    $('#modal-overlay').classList.add('hidden');
    updateFrameVisibility();
  }

  $('#admin-close-btn').addEventListener('click', () => nui('adminClose').then(hideAdmin));
  $('#admin-search').addEventListener('input', renderAdminTable);

  async function refreshAdminList() {
    adminDealerships = (await nui('adminRefresh')) || [];
    renderAdminTable();
  }

  function renderAdminTable() {
    const q = $('#admin-search').value.trim().toLowerCase();
    const list = adminDealerships.filter((d) => d.label.toLowerCase().includes(q) || d.name.toLowerCase().includes(q) || d.job.toLowerCase().includes(q));

    const tbody = $('#admin-table tbody');
    tbody.innerHTML = '';
    $('#admin-empty').classList.toggle('hidden', list.length > 0);

    list.forEach((d) => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${d.label} <span class="mono">(${d.name})</span></td>
        <td>${d.job}</td>
        <td>${titleCase(d.type)}</td>
        <td>${money(d.balance)}</td>
        <td><span class="source-tag ${d.source}">${d.source === 'registry' ? 'Runtime' : 'Config'}</span></td>
        <td class="row-actions"></td>
      `;
      const actions = tr.querySelector('.row-actions');
      actions.appendChild(smallBtn('Manage', () => nui('adminManageDealership', { dealership: d.name })));
      actions.appendChild(smallBtn('Balance', () => openSetBalanceModal(d)));
      actions.appendChild(smallBtn('Owner', () => openAssignOwnerModal(d)));
      if (d.source === 'registry') {
        const delBtn = smallBtn('Delete', () => openDeleteModal(d));
        delBtn.classList.add('danger');
        delBtn.classList.remove('ghost');
        actions.appendChild(delBtn);
      }
      tbody.appendChild(tr);
    });
  }

  function openSetBalanceModal(d) {
    openModal({
      title: `Set balance - ${d.label}`,
      fields: [{ label: 'New balance', type: 'number', default: d.balance, min: 0 }],
      confirmLabel: 'Save',
      onConfirm: async ([amount]) => {
        const res = await nui('adminSetBalance', { dealership: d.name, amount });
        if (res.ok) { toast('Balance updated', money(amount), 'success'); refreshAdminList(); }
        else toast('Failed', titleCase(res.result), 'error');
      },
    });
  }

  function openAssignOwnerModal(d) {
    openModal({
      title: `Assign owner - ${d.label}`,
      body: 'Target player must be online. This sets them to this dealership\'s job at the Owner grade. Defaults to your own player ID - change it to assign someone else.',
      fields: [{ label: 'Player ID', type: 'number', default: adminMyPlayerId || '', min: 1 }],
      confirmLabel: 'Assign',
      onConfirm: async ([targetId]) => {
        const res = await nui('adminAssignOwner', { dealership: d.name, targetId });
        if (res.ok) toast('Owner assigned', `Player #${targetId} is now owner of ${d.label}.`, 'success');
        else toast('Failed', titleCase(res.result), 'error');
      },
    });
  }

  function openDeleteModal(d) {
    openModal({
      title: `Delete ${d.label}?`,
      body: 'This permanently removes the dealership, its zones, and its lighting. Inventory and sales history are kept. This cannot be undone.',
      confirmLabel: 'Delete',
      onConfirm: async () => {
        const res = await nui('adminDeleteDealership', { dealership: d.name });
        if (res.ok) { toast('Dealership deleted', d.label, 'success'); refreshAdminList(); }
        else toast('Delete failed', titleCase(res.result), 'error');
      },
    });
  }

  // ---------------------------------------------------------------------
  // Vehicle catalog management (admin console)
  // ---------------------------------------------------------------------
  $('#catalog-search').addEventListener('input', renderCatalogAdminTable);
  $('#btn-add-catalog-vehicle').addEventListener('click', () => openCatalogVehicleModal(null));

  async function loadCatalogAdmin() {
    adminCatalog = (await nui('adminGetCatalog')) || [];
    renderCatalogAdminTable();
  }

  async function refreshCatalogAdmin() {
    adminCatalog = (await nui('adminGetCatalog')) || [];
    renderCatalogAdminTable();
  }

  function renderCatalogAdminTable() {
    const q = $('#catalog-search').value.trim().toLowerCase();
    const list = adminCatalog.filter((v) => v.label.toLowerCase().includes(q) || v.model.toLowerCase().includes(q));

    const tbody = $('#catalog-admin-table tbody');
    tbody.innerHTML = '';

    list.forEach((v) => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="mono">${v.model}</td>
        <td>${v.label}</td>
        <td>${titleCase(v.category)}</td>
        <td>${money(v.msrp)}</td>
        <td>${titleCase(v.rarity)}</td>
        <td><span class="source-tag ${v.source === 'custom' ? 'registry' : 'config'}">${v.source === 'custom' ? 'Custom' : 'Built-in'}</span></td>
        <td class="row-actions"></td>
      `;
      const actions = tr.querySelector('.row-actions');
      actions.appendChild(smallBtn('Edit', () => openCatalogVehicleModal(v)));
      if (v.source === 'custom') {
        const delBtn = smallBtn('Delete', () => openDeleteCatalogVehicleModal(v));
        delBtn.classList.add('danger');
        delBtn.classList.remove('ghost');
        actions.appendChild(delBtn);
      }
      tbody.appendChild(tr);
    });
  }

  function openCatalogVehicleModal(existing) {
    const isEdit = !!existing;
    openModal({
      title: isEdit ? `Edit ${existing.label}` : 'Add vehicle to catalog',
      body: isEdit && existing.source === 'config'
        ? "This is a built-in vehicle - you can edit its details, but it can't be removed here."
        : 'Model must be the exact spawn code (e.g. sultanrs), not the display name.',
      fields: [
        { label: 'Model (spawn code)', type: 'text', default: existing ? existing.model : '' },
        { label: 'Display label', type: 'text', default: existing ? existing.label : '' },
        { label: 'Category', type: 'select', default: existing ? existing.category : adminCategories[0], options: adminCategories.map((c) => ({ value: c, label: titleCase(c) })) },
        { label: 'MSRP', type: 'number', default: existing ? existing.msrp : 30000, min: 1 },
        { label: 'Rarity', type: 'select', default: existing ? existing.rarity : 'common', options: adminRarities.map((r) => ({ value: r, label: titleCase(r) })) },
      ],
      confirmLabel: isEdit ? 'Save changes' : 'Add vehicle',
      onConfirm: async ([model, label, category, msrp, rarity]) => {
        if (isEdit && existing.model !== model) {
          toast('Model can\'t be changed', 'Delete and re-add it under the new model instead.', 'error');
          return;
        }

        const check = await nui('checkModelValid', { model });
        if (!check.valid) {
          toast('Heads up', `"${model}" doesn't look like a streamed model on your own client - saving anyway, but double check the spawn code.`, 'error');
        }

        const res = await nui('adminUpsertCatalogVehicle', { vehicle: { model, label, category, msrp, rarity } });
        if (res.ok) { toast(isEdit ? 'Vehicle updated' : 'Vehicle added', label, 'success'); refreshCatalogAdmin(); }
        else toast('Save failed', titleCase(res.result), 'error');
      },
    });
  }

  function openDeleteCatalogVehicleModal(v) {
    openModal({
      title: `Remove ${v.label} from the catalog?`,
      body: 'Dealerships will no longer be able to order this vehicle. Any already in stock are unaffected.',
      confirmLabel: 'Remove',
      onConfirm: async () => {
        const res = await nui('adminRemoveCatalogVehicle', { model: v.model });
        if (res.ok) { toast('Vehicle removed', v.label, 'success'); refreshCatalogAdmin(); }
        else toast('Remove failed', titleCase(res.result), 'error');
      },
    });
  }
})();
