// VS Code Dark+ on screen; paper reports retain a white background.
export const reportTheme=`
.report-document .event-summary-table th:first-child,.report-document .event-summary-table td:first-child,.report-document .event-coverage-table th:nth-child(2),.report-document .event-coverage-table td:nth-child(2){min-width:110px;white-space:nowrap;overflow-wrap:normal;word-break:normal}
.event-message{white-space:pre-wrap;overflow-wrap:anywhere}.selected-event{border-left-width:4px}.report-timeline{break-inside:avoid}.report-document button{font:600 12px "Segoe UI",sans-serif;cursor:pointer;padding:7px 10px;border:1px solid #007acc;border-radius:3px;background:#0e639c;color:white}.report-document button:disabled{opacity:.55;cursor:wait}.report-document button:focus-visible{outline:2px solid #75beff;outline-offset:3px}
@media screen{
html{color-scheme:dark}.report-standalone{background:#1e1e1e;color:#d4d4d4}
.report-document{background:#252526;color:#d4d4d4;border-color:#454545;border-radius:4px}
.report-document h1,.report-document h2,.report-document h3,.report-meta dd{color:#d4d4d4}
.report-document .report-kicker{color:#4fc1ff}.report-heading{border-color:#007acc}
.report-subtitle,.report-meta dt,.report-document .report-muted,.report-document .report-footer{color:#b4b4b4}
.report-document .report-mode{background:#18354a;color:#9cdcfe;border-color:#31536a}
.report-document .report-mode.simulated{background:#3b321c;color:#dcdcaa;border-color:#6b5b28}
.report-section,.report-document .report-footer{border-color:#454545}.report-counts span{background:#333333}
.report-document .report-badge{background:#333333;color:#cccccc;border-color:#777777}
.report-document .report-badge.healthy{background:#173a2a;color:#89d185;border-color:#48764a}
.report-document .report-badge.warning{background:#3b321c;color:#dcca81;border-color:#87722c}
.report-document .report-badge.critical{background:#4b2224;color:#f48771;border-color:#a34b4b}
.report-finding{background:#332f20;border-color:#cca700}.report-finding.critical{background:#3f2425;border-color:#f14c4c}
.report-document .report-next{color:#9cdcfe}.report-document th{background:#333333;color:#cccccc}
.report-document td,.report-document th{border-color:#454545}.report-document .report-note{background:#2d2d30;color:#cccccc}
.report-document summary,.report-document a{color:#4fc1ff}.report-document .report-timeline{border-color:#569cd6}
.report-document .selected-event{background:#19344a;padding:12px 16px;border-color:#007acc}
.report-toolbar button,.report-toolbar a{background:#333333;color:#d4d4d4;border-color:#686868;border-radius:3px}
}
@media print{html{color-scheme:light}.report-timeline p{max-height:none;overflow:visible}.report-document button{display:none!important}.report-document details{display:block}.report-document details>*{display:block!important}}
`;
