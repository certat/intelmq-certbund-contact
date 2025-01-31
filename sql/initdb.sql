BEGIN;

/*
 Template table containing with elements for automatic tables
 */
CREATE TEMP TABLE automatic_templ (
    import_source VARCHAR(500) NOT NULL CHECK (import_source <> ''),
    import_time TIMESTAMP NOT NULL
);


/* Sector to classify organisations.
*/
CREATE TABLE sector (
  sector_id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL
);

/*
  Organisation and Contact
*/

-- Template to use for the actual tables. This makes sure their schemas
-- are defined in the same way.
CREATE TEMP TABLE organisation_templ (
    -- The name of the organisation.
    -- In the ripe db there are names identical for more than one
    -- organisation, so we can not make this unique.
    name VARCHAR(500) NOT NULL,

    -- The sector the organisation belongs to.
    sector_id INTEGER,

    -- Comments about the organisation
    comment TEXT NOT NULL DEFAULT '',

    -- The org: nic handle in the RIPE DB, if available
    ripe_org_hdl VARCHAR(100) NOT NULL DEFAULT '',

    -- The Trusted Introducer (TI) handle or URL: for example
    -- https://www.trusted-introducer.org/directory/teams/certat.html
    ti_handle VARCHAR(500) NOT NULL DEFAULT '',

    -- The FIRST.org handle or URL: for example
    -- https://api.first.org/data/v1/teams?q=aconet-cert
    first_handle VARCHAR(500) NOT NULL DEFAULT ''
);


CREATE TABLE organisation (
    organisation_id SERIAL PRIMARY KEY,
    LIKE organisation_templ INCLUDING ALL,

    FOREIGN KEY (sector_id) REFERENCES sector(sector_id)
);


CREATE TABLE organisation_automatic (
    organisation_automatic_id SERIAL PRIMARY KEY,
    LIKE organisation_templ INCLUDING ALL,
    LIKE automatic_templ INCLUDING ALL,

    FOREIGN KEY (sector_id) REFERENCES sector(sector_id)
);


CREATE TABLE organisation_annotation (
    organisation_annotation_id SERIAL PRIMARY KEY,
    organisation_id INTEGER NOT NULL,
    annotation JSON NOT NULL,

    FOREIGN KEY (organisation_id) REFERENCES organisation(organisation_id)
);

CREATE INDEX organisation_annotation_organisation_idx
          ON organisation_annotation (organisation_id);



CREATE TEMP TABLE contact_templ (
    firstname VARCHAR (500) NOT NULL DEFAULT '',
    lastname  VARCHAR (500) NOT NULL DEFAULT '',
    tel       VARCHAR (500) NOT NULL DEFAULT '',

    -- The full fingerprint of the OpenPGP pubkey of the contact as GnuPG
    -- would accept it to specify a user ID.
    -- (This avoids ambiguities in case that there are duplicated key IDs.)
    openpgp_fpr VARCHAR(128) NOT NULL DEFAULT '',

    -- the email-address of the contact
    email VARCHAR(100) NOT NULL,

    comment TEXT NOT NULL DEFAULT ''
);


CREATE TABLE contact (
    contact_id SERIAL PRIMARY KEY,
    LIKE contact_templ INCLUDING ALL,
    organisation_id INTEGER NOT NULL,

    FOREIGN KEY (organisation_id) REFERENCES organisation (organisation_id)
);

CREATE INDEX contact_organisation_idx ON contact (organisation_id);


CREATE TABLE contact_automatic (
    contact_automatic_id SERIAL PRIMARY KEY,
    LIKE contact_templ INCLUDING ALL,
    LIKE automatic_templ INCLUDING ALL,
    organisation_automatic_id INTEGER NOT NULL,

    FOREIGN KEY (organisation_automatic_id)
     REFERENCES organisation_automatic (organisation_automatic_id)
);

CREATE INDEX contact_automatic_organisation_idx
          ON contact_automatic (organisation_automatic_id);

/*
  Network related tables, such as:
  AS, IP-Ranges, FQDN
*/

-- Annotations for autonomous systems
CREATE TABLE autonomous_system_annotation (
    autonomous_system_annotation_id SERIAL PRIMARY KEY,
    asn BIGINT NOT NULL,
    annotation JSON NOT NULL
);

CREATE INDEX autonomous_system_annotation_asn_idx
          ON autonomous_system_annotation (asn);


-- A network
-- See also: https://www.ripe.net/manage-ips-and-asns/db/support/documentation/ripe-database-documentation/rpsl-object-types/4-2-descriptions-of-primary-objects/4-2-4-description-of-the-inetnum-object
CREATE TEMP TABLE network_templ (
    -- Network address as CIDR.
    address cidr NOT NULL,

    comment TEXT NOT NULL DEFAULT ''
);


CREATE TABLE network (
    network_id SERIAL PRIMARY KEY,
    LIKE network_templ INCLUDING ALL
);

CREATE TABLE network_automatic (
    network_automatic_id SERIAL PRIMARY KEY,
    LIKE network_templ INCLUDING ALL,
    LIKE automatic_templ INCLUDING ALL,

    UNIQUE (address, import_source)
);


-- Indexes on the cidr column to improve queries that look up a network
-- based on an IP-address. The default btree index of PostgreSQL is not
-- used for those queries, so we need to do it in some other way. A
-- simple way is to have indexes for the lower and upper bounds of the
-- address range represented by the cidr value, so that's what we do
-- here. The main downside is that the queries will have to use the same
-- expressions as the ones used in the indexes. E.g. a query matching
-- network that contain the IP-address ip and using n as the local alias
-- for the table should use a where clause condition of the form
--
--   inet(host(network(n.address))) <= ip
--   AND ip <= inet(host(broadcast(n.address)))
--
-- FIXME: In PostgreSQL 9.4 there's GiST indexes for the inet and cidr
-- types (see http://www.postgresql.org/docs/9.4/static/release-9-4.html).
-- We cannot use that at the moment, because we still need to support
-- PostgreSQL 9.3 which is the version available in Ubuntu 14.04LTS.
--
-- XXX COMMENT Aaron: please let's simply depend on postgresql >= 9.4
-- IMHO that's okay to demand this XXX
--
CREATE INDEX network_cidr_lower_idx
          ON network ((inet(host(network(address)))));
CREATE INDEX network_cidr_upper_idx
          ON network ((inet(host(broadcast(address)))));

CREATE INDEX network_automatic_cidr_lower_idx
          ON network_automatic ((inet(host(network(address)))));
CREATE INDEX network_automatic_cidr_upper_idx
          ON network_automatic ((inet(host(broadcast(address)))));

CREATE INDEX network_automatic_cidr_gist_idx ON network_automatic
       USING gist (address inet_ops);


-- Annotations for networks
CREATE TABLE network_annotation (
    network_annotation_id SERIAL PRIMARY KEY,
    network_id INTEGER NOT NULL,
    annotation JSON NOT NULL,

    FOREIGN KEY (network_id) REFERENCES network(network_id)
);

CREATE INDEX network_annotation_network_idx
          ON network_annotation (network_id);




-- A fully qualified domain name
CREATE TEMP TABLE fqdn_templ (
    -- The fully qualified domain name
    fqdn TEXT NOT NULL,

    comment TEXT NOT NULL DEFAULT ''
);


CREATE TABLE fqdn (
    fqdn_id SERIAL PRIMARY KEY,
    LIKE fqdn_templ INCLUDING ALL
);

CREATE INDEX fqdn_fqdn_idx ON fqdn (fqdn);


CREATE TABLE fqdn_automatic (
    fqdn_automatic_id SERIAL PRIMARY KEY,
    LIKE fqdn_templ INCLUDING ALL,
    LIKE automatic_templ INCLUDING ALL,

    UNIQUE (fqdn, import_source)
);


CREATE TABLE fqdn_annotation (
    fqdn_annotation_id SERIAL PRIMARY KEY,
    fqdn_id INTEGER NOT NULL,
    annotation JSON NOT NULL,

    FOREIGN KEY (fqdn_id) REFERENCES fqdn(fqdn_id)
);

CREATE INDEX fqdn_annotation_fqdn_idx
          ON fqdn_annotation (fqdn_id);


-- Routing information, useful as a mapping from network addresses to
-- ASNs.
CREATE TABLE route_automatic (
    route_automatic_id SERIAL PRIMARY KEY,
    address CIDR NOT NULL,
    asn BIGINT NOT NULL,
    LIKE automatic_templ INCLUDING ALL,

    -- The data from ripe.db.route.gz and ripe.db.route6.gz has cases
    -- where the same network address is associated with multiple ASNs,
    -- so we cannot have a constraint on just (address, import_source).
    UNIQUE (address, asn, import_source)
);

CREATE INDEX route_automatic_cidr_gist_idx ON route_automatic
       USING gist (address inet_ops);


-- Information about national CERTs

-- national_cert relates a country code to the organisation considered
-- the national CERT for that country.
CREATE TEMP TABLE national_cert_templ (
    -- The country code for the CERT
    country_code CHARACTER(2) NOT NULL,

    comment TEXT NOT NULL DEFAULT ''
);


CREATE TABLE national_cert (
    national_cert_id SERIAL PRIMARY KEY,
    LIKE national_cert_templ INCLUDING ALL,

    -- The ID of the organisation representing the CERT
    organisation_id INTEGER NOT NULL,

    FOREIGN KEY (organisation_id) REFERENCES organisation (organisation_id)
);

CREATE INDEX national_cert_country_code_idx
          ON national_cert (country_code);


-- Like national_cert but for automatically maintained data.
CREATE TABLE national_cert_automatic (
    national_cert_automatic_id SERIAL PRIMARY KEY,
    LIKE national_cert_templ INCLUDING ALL,

    organisation_automatic_id INTEGER NOT NULL,

    LIKE automatic_templ INCLUDING ALL,

    FOREIGN KEY (organisation_automatic_id)
     REFERENCES organisation_automatic (organisation_automatic_id)
);

CREATE INDEX national_cert_automatic_country_code_idx
          ON national_cert_automatic (country_code);


/*
 Relations A_to_B
 Some of them (contact_to_X) carry an additional column TTL
 See also https://www.ripe.net/manage-ips-and-asns/db/support/documentation/ripe-database-documentation/ripe-database-structure/3-1-list-of-primary-objects
*/
CREATE TABLE organisation_to_asn (
    organisation_id INTEGER,
    asn BIGINT,

    PRIMARY KEY (organisation_id, asn),

    FOREIGN KEY (organisation_id) REFERENCES organisation (organisation_id)
);

CREATE INDEX organisation_to_asn_asn_idx
    ON organisation_to_asn (asn);


CREATE TABLE organisation_to_asn_automatic (
    organisation_automatic_id INTEGER,
    asn BIGINT,
    LIKE automatic_templ INCLUDING ALL,

    PRIMARY KEY (organisation_automatic_id, asn),
    FOREIGN KEY (organisation_automatic_id)
     REFERENCES organisation_automatic (organisation_automatic_id)
);

CREATE INDEX organisation_to_asn_automatic_asn_idx
    ON organisation_to_asn_automatic (asn);


CREATE TABLE organisation_to_network (
    organisation_id INTEGER,
    network_id INTEGER,

    PRIMARY KEY (organisation_id, network_id),

    FOREIGN KEY (organisation_id) REFERENCES organisation (organisation_id),
    FOREIGN KEY (network_id) REFERENCES network (network_id)
);

CREATE TABLE organisation_to_network_automatic (
    organisation_automatic_id INTEGER,
    network_automatic_id INTEGER,
    LIKE automatic_templ INCLUDING ALL,

    PRIMARY KEY (organisation_automatic_id, network_automatic_id),

    FOREIGN KEY (organisation_automatic_id)
     REFERENCES organisation_automatic (organisation_automatic_id),
    FOREIGN KEY (network_automatic_id)
     REFERENCES network_automatic (network_automatic_id)
);


CREATE TABLE organisation_to_fqdn (
    organisation_id INTEGER,
    fqdn_id INTEGER,

    PRIMARY KEY (organisation_id, fqdn_id),

    FOREIGN KEY (organisation_id) REFERENCES organisation (organisation_id),
    FOREIGN KEY (fqdn_id) REFERENCES fqdn (fqdn_id)
);

CREATE TABLE organisation_to_fqdn_automatic (
    organisation_automatic_id INTEGER,
    fqdn_automatic_id INTEGER,
    LIKE automatic_templ INCLUDING ALL,

    PRIMARY KEY (organisation_automatic_id, fqdn_automatic_id),

    FOREIGN KEY (organisation_automatic_id)
     REFERENCES organisation_automatic (organisation_automatic_id),
    FOREIGN KEY (fqdn_automatic_id)
     REFERENCES fqdn_automatic (fqdn_automatic_id)
);



-- Table to hold known status information about an email address. If no
-- status information is known, there is no entry in the table, which
-- means the email is enabled.
CREATE TABLE email_status (
    email VARCHAR(100) PRIMARY KEY,
    enabled BOOLEAN NOT NULL,
    added TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- Tags for email addresses. These apply to any email address, including
-- in particular email addresses of automatically maintained contacts.

CREATE TABLE tag_name (
    tag_name_id SERIAL PRIMARY KEY,
    tag_name TEXT NOT NULL,
    tag_name_order INTEGER NOT NULL,

    UNIQUE (tag_name)
);

CREATE TABLE tag (
    tag_id SERIAL PRIMARY KEY,
    tag_name_id INTEGER NOT NULL,
    tag_value TEXT NOT NULL,
    tag_description TEXT NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT false,

    UNIQUE (tag_name_id, tag_value),
    FOREIGN KEY (tag_name_id) REFERENCES tag_name (tag_name_id)
);

-- Unique index to ensure that for each tag_name, there's at most one
-- tag marked as default.
CREATE UNIQUE INDEX tag_unique_default_tags_idx
    ON tag (tag_name_id)
 WHERE is_default;


CREATE TABLE email_tag (
    email VARCHAR(100) NOT NULL,
    tag_id INTEGER NOT NULL,

    PRIMARY KEY (email, tag_id),

    FOREIGN KEY (tag_id) REFERENCES tag (tag_id)
);


CREATE INDEX email_tag_email_idx
          ON email_tag (email);


-- View to present the tags as annotations so that the contact bot only
-- has to deal with annotations.
CREATE VIEW email_annotation (email, annotation)
  AS SELECT email,
            json_build_object('tag', tag_name || ':' || tag_value)
       FROM email_tag
       JOIN tag USING (tag_id)
       JOIN tag_name USING (tag_name_id);


CREATE OR REPLACE FUNCTION email_annotations(email_address VARCHAR(100))
RETURNS JSON AS
$$
DECLARE
    annotations JSON;
BEGIN
WITH
  email_tags (tag_name_id, annotation)
    AS (SELECT tag_name_id,
               json_build_object('tag',
                                 tag_name.tag_name || ':' || tag.tag_value)
               AS annotation
          FROM email_tag
          JOIN tag USING (tag_id)
          JOIN tag_name USING (tag_name_id)
         WHERE email_tag.email = email_address),
  default_tags (tag_name_id, default_tag)
    AS (SELECT tag_name_id,
               MIN(tag_name.tag_name || ':' || tag.tag_value)
               FILTER (WHERE is_default)
               AS default_tag
          FROM tag JOIN tag_name USING (tag_name_id)
      GROUP BY tag_name_id),
  default_annotations (tag_name_id, default_annotation)
    AS (SELECT tag_name_id,
               CASE WHEN default_tag IS NULL THEN NULL
                    ELSE json_build_object('tag', default_tag)
               END AS default_annotation
         FROM default_tags)
SELECT json_agg(COALESCE(annotation, default_annotation))
       FILTER (WHERE COALESCE(annotation, default_annotation) IS NOT NULL)
       INTO annotations
  FROM email_tags RIGHT OUTER JOIN default_annotations USING (tag_name_id);

RETURN coalesce(annotations, '[]'::JSON);
END;
$$ LANGUAGE plpgsql STABLE;


COMMIT;
