-- Run libx509pq/create_functions.sql first.


-- As the "postgres" user.

CREATE EXTENSION pgcrypto;


-- As the "certwatch" user.

CREATE TABLE ca (
	ID						serial,
	NAME					text		NOT NULL,
	PUBLIC_KEY				bytea		NOT NULL,
	BRAND					text,
	LINTING_APPLIES			boolean		DEFAULT TRUE,
	NO_OF_CERTS_ISSUED		bigint		DEFAULT 0	NOT NULL,
	CONSTRAINT ca_pk
		PRIMARY KEY (ID)
);

CREATE UNIQUE INDEX ca_uniq
	ON ca (NAME text_pattern_ops, PUBLIC_KEY);

CREATE INDEX ca_name
	ON ca (lower(NAME) text_pattern_ops);

CREATE INDEX ca_brand
	ON ca (lower(BRAND) text_pattern_ops);

CREATE INDEX ca_name_reverse
	ON ca (reverse(lower(NAME)) text_pattern_ops);

CREATE INDEX ca_brand_reverse
	ON ca (reverse(lower(BRAND)) text_pattern_ops);

CREATE INDEX ca_linting_applies
	ON ca (LINTING_APPLIES, ID);

CREATE TABLE certificate (
	ID						serial,
	CERTIFICATE				bytea		NOT NULL,
	ISSUER_CA_ID			integer		NOT NULL,
	CABLINT_CACHED_AT		timestamp,
	X509LINT_CACHED_AT		timestamp,
	CONSTRAINT c_pk
		PRIMARY KEY (ID),
	CONSTRAINT c_ica_fk
		FOREIGN KEY (ISSUER_CA_ID)
		REFERENCES ca(ID)
);

CREATE INDEX c_ica_typecanissue
	ON certificate (ISSUER_CA_ID, x509_canIssueCerts(CERTIFICATE));

CREATE INDEX c_ica_notbefore
	ON certificate (ISSUER_CA_ID, x509_notBefore(CERTIFICATE));

CREATE INDEX c_notafter_ica
	ON certificate (x509_notAfter(CERTIFICATE), ISSUER_CA_ID);

CREATE INDEX c_serial_ica
	ON certificate (x509_serialNumber(CERTIFICATE), ISSUER_CA_ID);

CREATE INDEX c_sha1
	ON certificate (digest(CERTIFICATE, 'sha1'));

CREATE UNIQUE INDEX c_sha256
	ON certificate (digest(CERTIFICATE, 'sha256'));

CREATE INDEX c_spki_sha1
	ON certificate (digest(x509_publicKey(CERTIFICATE), 'sha1'));

CREATE INDEX c_spki_sha256
	ON certificate (digest(x509_publicKey(CERTIFICATE), 'sha256'));

CREATE INDEX c_subject_sha1
	ON certificate (digest(x509_name(CERTIFICATE), 'sha1'));

CREATE TABLE invalid_certificate (
	CERTIFICATE_ID			integer,
	PROBLEMS				text,
	CERTIFICATE_AS_LOGGED	bytea,
	CONSTRAINT ic_pk
		PRIMARY KEY (CERTIFICATE_ID),
	CONSTRAINT ic_c_fk
		FOREIGN KEY (CERTIFICATE_ID)
		REFERENCES certificate(ID)
);

CREATE TYPE name_type AS ENUM (
	'commonName', 'organizationName', 'emailAddress',
	'rfc822Name', 'dNSName', 'iPAddress', 'organizationalUnitName'
);

CREATE TABLE certificate_identity (
	CERTIFICATE_ID			integer		NOT NULL,
	NAME_TYPE				name_type	NOT NULL,
	NAME_VALUE				text		NOT NULL,
	ISSUER_CA_ID			integer,
	CONSTRAINT ci_c_fk
		FOREIGN KEY (CERTIFICATE_ID)
		REFERENCES certificate(ID),
	CONSTRAINT ci_ca_fk
		FOREIGN KEY (ISSUER_CA_ID)
		REFERENCES ca(ID)
);

CREATE UNIQUE INDEX ci_uniq
	ON certificate_identity (CERTIFICATE_ID, lower(NAME_VALUE) text_pattern_ops, NAME_TYPE);

CREATE INDEX ci_forward
	ON certificate_identity (lower(NAME_VALUE) text_pattern_ops, ISSUER_CA_ID, NAME_TYPE);

CREATE INDEX ci_reverse
	ON certificate_identity (reverse(lower(NAME_VALUE)) text_pattern_ops, ISSUER_CA_ID, NAME_TYPE);

CREATE INDEX ci_ca
	ON certificate_identity (ISSUER_CA_ID, lower(NAME_VALUE) text_pattern_ops, NAME_TYPE);

CREATE INDEX ci_ca_reverse
	ON certificate_identity (ISSUER_CA_ID, reverse(lower(NAME_VALUE)) text_pattern_ops, NAME_TYPE);


CREATE TABLE ca_certificate (
	CERTIFICATE_ID			integer,
	CA_ID					integer,
	CONSTRAINT cac_pk
		PRIMARY KEY (CERTIFICATE_ID),
	CONSTRAINT cac_c_fk
		FOREIGN KEY (CERTIFICATE_ID)
		REFERENCES certificate(ID),
	CONSTRAINT cac_ca_fk
		FOREIGN KEY (CA_ID)
		REFERENCES ca(ID)
);

CREATE INDEX cac_ca_cert
	ON ca_certificate (CA_ID, CERTIFICATE_ID);


CREATE TABLE ct_log (
	ID						smallint,
	URL						text,
	NAME					text,
	PUBLIC_KEY				bytea,
	LATEST_ENTRY_ID			integer,
	LATEST_UPDATE			timestamp,
	OPERATOR				text,
	INCLUDED_IN_CHROME		integer,
	IS_ACTIVE				boolean,
	LATEST_STH_TIMESTAMP	timestamp,
	MMD_IN_SECONDS			integer,
	CHROME_ISSUE_NUMBER		integer,
	NON_INCLUSION_STATUS	text,
	CONSTRAINT ctl_pk
		PRIMARY KEY (ID),
	CONSTRAINT crl_url_unq
		UNIQUE (URL)
);

CREATE UNIQUE INDEX ctl_sha256_pubkey
	ON ct_log (digest(PUBLIC_KEY, 'sha256'));

CREATE TABLE ct_log_entry (
	CERTIFICATE_ID	integer,
	CT_LOG_ID		smallint,
	ENTRY_ID		integer,
	ENTRY_TIMESTAMP	timestamp,
	CONSTRAINT ctle_pk
		PRIMARY KEY (CERTIFICATE_ID, CT_LOG_ID, ENTRY_ID),
	CONSTRAINT ctle_c_fk
		FOREIGN KEY (CERTIFICATE_ID)
		REFERENCES certificate(ID),
	CONSTRAINT ctle_ctl_fk
		FOREIGN KEY (CT_LOG_ID)
		REFERENCES ct_log(ID)
);

CREATE INDEX ctle_le
	ON ct_log_entry (CT_LOG_ID, ENTRY_ID);

CREATE INDEX ctle_el
	ON ct_log_entry (ENTRY_ID, CT_LOG_ID);

CREATE TYPE linter_type AS ENUM (
	'cablint', 'x509lint'
);

CREATE TABLE linter_version (
	VERSION_STRING	text,
	GIT_COMMIT		bytea,
	DEPLOYED_AT		timestamp,
	LINTER			linter_type
);

CREATE UNIQUE INDEX lv_li_da
	ON linter_version(LINTER, DEPLOYED_AT);


CREATE TABLE lint_issue (
	ID				serial,
	SEVERITY		text,
	ISSUE_TEXT		text,
	LINTER			linter_type,
	CONSTRAINT li_pk
		PRIMARY KEY (ID),
	CONSTRAINT li_it_unq
		UNIQUE (SEVERITY, ISSUE_TEXT),
	CONSTRAINT li_li_se_it_unq
		UNIQUE (LINTER, SEVERITY, ISSUE_TEXT)
);

CREATE TABLE lint_cert_issue (
	ID					bigserial,
	CERTIFICATE_ID		integer,
	LINT_ISSUE_ID		integer,
	ISSUER_CA_ID		integer,
	NOT_BEFORE			timestamp,
	CONSTRAINT lci_pk
		PRIMARY KEY (ID),
	CONSTRAINT lci_c_fk
		FOREIGN KEY (CERTIFICATE_ID)
		REFERENCES certificate(ID),
	CONSTRAINT lci_ci_fk
		FOREIGN KEY (LINT_ISSUE_ID)
		REFERENCES lint_issue(ID),
	CONSTRAINT lci_ca_fk
		FOREIGN KEY (ISSUER_CA_ID)
		REFERENCES ca(ID)
);

CREATE INDEX lci_c_ci
	ON lint_cert_issue (CERTIFICATE_ID, LINT_ISSUE_ID);

CREATE INDEX lci_ca_ci_nb_c
	ON lint_cert_issue (ISSUER_CA_ID, LINT_ISSUE_ID, NOT_BEFORE, CERTIFICATE_ID);

CREATE INDEX lci_ci_nb
	ON lint_cert_issue (LINT_ISSUE_ID, NOT_BEFORE);

CREATE INDEX lci_nb_ca_ci
	ON lint_cert_issue (NOT_BEFORE, ISSUER_CA_ID, LINT_ISSUE_ID);

GRANT SELECT ON ca TO crtsh;

GRANT USAGE ON ca_id_seq TO crtsh;

GRANT SELECT ON certificate TO crtsh;

GRANT USAGE ON certificate_id_seq TO crtsh;

GRANT SELECT ON certificate_identity TO crtsh;

GRANT SELECT ON ca_certificate TO crtsh;

GRANT SELECT ON ct_log TO crtsh;

GRANT SELECT ON ct_log_entry TO crtsh;

GRANT SELECT ON lint_issue TO crtsh;

GRANT SELECT ON lint_cert_issue TO crtsh;


\i lint_cached.fnc
\i download_cert.fnc
\i extract_cert_names.fnc
\i get_ca_primary_name_attribute.fnc
\i get_parameter.fnc
\i html_escape.fnc
\i import_cert.fnc
\i import_ct_cert.fnc
\i web_apis.fnc
