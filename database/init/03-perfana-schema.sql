--
-- Perfana Consolidated Database Schema
-- Generated from production pg_dump with extensions prepended
--
-- This file is loaded by the ConsolidatedSchema migration.
-- It contains the complete database schema including:
--   - Extensions (uuid-ossp, timescaledb, timescaledb_toolkit)
--   - Custom types and enums
--   - Functions (utility, trigger, RLS helper)
--   - Tables with all columns, defaults, and constraints
--   - Views
--   - Indexes
--   - Triggers
--   - Foreign key constraints
--   - Row-level security policies
--

--
-- Extensions
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit WITH SCHEMA public;

--
-- PostgreSQL database dump
--


-- Dumped from database version 15.15 (Ubuntu 15.15-1.pgdg22.04+1)
-- Dumped by pg_dump version 15.14 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- Schema public already exists


--
-- Name: tracing_instances_tracing_ui_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.tracing_instances_tracing_ui_enum AS ENUM (
    'tempo',
    'jaeger',
    'elastic'
);


--
-- Name: tags_hash(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tags_hash(tags text[]) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
      SELECT md5(COALESCE(array_to_string(tags, ','), ''))
    $$;

--
-- Name: can_access_resource(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_access_resource(resource_org_id uuid, resource_team_id uuid, resource_created_by text) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
    BEGIN
      IF is_global_admin() THEN
        RETURN TRUE;
      END IF;
      IF resource_org_id IS NULL AND resource_team_id IS NULL AND resource_created_by IS NULL THEN
        RETURN TRUE;
      END IF;
      IF resource_org_id IS NULL THEN
        RETURN TRUE;
      END IF;
      IF resource_org_id = ANY(current_user_organizations()) THEN
        RETURN TRUE;
      END IF;
      IF resource_team_id IS NOT NULL AND resource_team_id = ANY(current_user_teams()) THEN
        RETURN TRUE;
      END IF;
      IF resource_created_by IS NOT NULL AND resource_created_by = current_user_id() THEN
        RETURN TRUE;
      END IF;
      RETURN FALSE;
    END;
    $$;


--
-- Name: can_modify_resource(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_modify_resource(resource_org_id uuid, resource_team_id uuid DEFAULT NULL::uuid, resource_created_by text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
      DECLARE
        user_id TEXT;
        user_orgs UUID[];
        user_teams UUID[];
        user_roles TEXT;
      BEGIN
        -- Global admins can modify everything
        IF is_global_admin() THEN
          RETURN TRUE;
        END IF;

        -- Get current user context
        user_id := current_user_id();
        user_orgs := current_user_organizations();
        user_teams := current_user_teams();
        user_roles := current_setting('app.current_user_roles', true);

        -- If no user context, deny access (fail-safe)
        IF user_id IS NULL THEN
          RETURN FALSE;
        END IF;

        -- Check if user is the resource owner/creator
        IF resource_created_by IS NOT NULL AND resource_created_by = user_id THEN
          RETURN TRUE;
        END IF;

        -- Resources without organization_id - check if user has org-admin role
        -- (stricter than read access for legacy data)
        IF resource_org_id IS NULL THEN
          -- For legacy resources, require org-admin to modify
          IF user_roles LIKE '%"org-admin"%' THEN
            RETURN TRUE;
          END IF;
          -- Regular users can only modify their own resources
          RETURN FALSE;
        END IF;

        -- Check if user is an org-admin in the resource's organization
        IF resource_org_id = ANY(user_orgs) THEN
          -- Check for org-level admin role
          IF user_roles LIKE '%"org-admin"%' THEN
            RETURN TRUE;
          END IF;
        END IF;

        -- Check team-level permissions
        IF resource_team_id IS NOT NULL AND resource_team_id = ANY(user_teams) THEN
          -- Check for team-level admin role
          IF user_roles LIKE '%"team-admin"%' THEN
            RETURN TRUE;
          END IF;
        END IF;

        -- Members can modify resources in their org/team
        -- This allows org-member and team-member to modify resources
        IF resource_org_id = ANY(user_orgs) THEN
          RETURN TRUE;
        END IF;

        IF resource_team_id IS NOT NULL AND resource_team_id = ANY(user_teams) THEN
          RETURN TRUE;
        END IF;

        -- Deny modification if no conditions match
        RETURN FALSE;
      END;
      $$;


--
-- Name: current_user_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_user_id() RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
    BEGIN
      RETURN current_setting('app.current_user_id', true);
    END;
    $$;


--
-- Name: current_user_organizations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_user_organizations() RETURNS uuid[]
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
    DECLARE
      orgs_json TEXT;
      org_array UUID[];
    BEGIN
      orgs_json := current_setting('app.current_user_organizations', true);
      IF orgs_json IS NULL OR orgs_json = '' OR orgs_json = '[]' THEN
        RETURN ARRAY[]::UUID[];
      END IF;
      SELECT array_agg(elem::UUID) INTO org_array
      FROM jsonb_array_elements_text(orgs_json::jsonb) AS elem;
      RETURN COALESCE(org_array, ARRAY[]::UUID[]);
    END;
    $$;


--
-- Name: current_user_teams(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_user_teams() RETURNS uuid[]
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
    DECLARE
      teams_json TEXT;
      team_array UUID[];
    BEGIN
      teams_json := current_setting('app.current_user_teams', true);
      IF teams_json IS NULL OR teams_json = '' OR teams_json = '[]' THEN
        RETURN ARRAY[]::UUID[];
      END IF;
      SELECT array_agg(elem::UUID) INTO team_array
      FROM jsonb_array_elements_text(teams_json::jsonb) AS elem;
      RETURN COALESCE(team_array, ARRAY[]::UUID[]);
    END;
    $$;


--
-- Name: is_global_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_global_admin() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
    DECLARE
      user_roles TEXT;
    BEGIN
      user_roles := current_setting('app.current_user_roles', true);
      RETURN user_roles IS NOT NULL AND (
        user_roles LIKE '%super-admin%' OR
        user_roles LIKE '%system-admin%'
      );
    END;
    $$;


--
-- Name: mark_results_fresh_on_analysis(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_results_fresh_on_analysis() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Only mark as fresh if this appears to be a real analysis update
  -- (i.e., when statistical data is being updated, not just stale status)
  IF (TG_OP = 'INSERT') OR 
     (TG_OP = 'UPDATE' AND (
       OLD.mean IS DISTINCT FROM NEW.mean OR
       OLD.median IS DISTINCT FROM NEW.median OR
       OLD.conclusion IS DISTINCT FROM NEW.conclusion OR
       OLD.compare_config IS DISTINCT FROM NEW.compare_config
     )) THEN
    -- This is a real analysis update, mark as fresh
    NEW.is_stale = false;
    NEW.stale_reason = null;
    NEW.stale_at = null;
    
    -- Set the config_hash_used to current config hash
    IF NEW.compare_config ? 'config_hash' THEN
      NEW.config_hash_used = NEW.compare_config->>'config_hash';
    END IF;
  END IF;

  -- Keep the existing config_hash_used if not explicitly provided
  IF NEW.config_hash_used IS NULL AND OLD.config_hash_used IS NOT NULL THEN
    NEW.config_hash_used = OLD.config_hash_used;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: mark_results_stale_on_config_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_results_stale_on_config_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only proceed if config_data actually changed
    IF OLD.config_data IS NOT DISTINCT FROM NEW.config_data THEN
        RETURN NEW;
    END IF;

    -- Mark corresponding ds_adapt_results as stale
    UPDATE ds_adapt_results
    SET
        is_stale = true,
        stale_reason = 'Configuration updated',
        stale_at = NOW()
    WHERE
        EXISTS (
            SELECT 1 FROM test_runs tr
            WHERE tr.test_run_id = ds_adapt_results.test_run_id
            AND tr.system_under_test_id = NEW.system_under_test_id
            AND tr.test_environment = NEW.test_environment
            AND tr.workload = NEW.workload
        )
        AND application_dashboard_id = NEW.application_dashboard_id
        AND panel_id = NEW.panel_id
        AND (
            (NEW.metric_name IS NULL) OR
            (metric_name = NEW.metric_name)
        )
        AND (
            -- Mark as stale if config_hash_used is null (legacy results) or doesn't match new hash
            config_hash_used IS NULL OR
            config_hash_used != NEW.config_hash
        )
        AND is_stale = false; -- Only update if not already stale

    RETURN NEW;
END;
$$;


--
-- Name: migrate_benchmark_from_mongodb(character varying, character varying, character varying, character varying, character varying, integer, character varying, jsonb, character varying, character varying, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.migrate_benchmark_from_mongodb(p_application character varying, p_test_environment character varying, p_test_type character varying, p_grafana character varying, p_dashboard_label character varying, p_dashboard_id integer, p_dashboard_uid character varying, p_panel jsonb, p_generic_check_id character varying DEFAULT NULL::character varying, p_application_dashboard_id character varying DEFAULT NULL::character varying, p_valid boolean DEFAULT true) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_benchmark_id uuid;
    v_system_id uuid;
BEGIN
    -- Find matching system_under_test
    SELECT id INTO v_system_id
    FROM public.systems_under_test
    WHERE name = p_application
    LIMIT 1;
    
    IF v_system_id IS NULL THEN
        RAISE EXCEPTION 'System under test with name % not found', p_application;
    END IF;
    
    -- Insert the benchmark (Grafana source)
    INSERT INTO public.benchmarks_new (
        system_under_test_id,
        test_environment,
        test_type,
        source,
        grafana_instance,
        dashboard_label,
        dashboard_id,
        dashboard_uid,
        configuration,
        generic_check_id,
        valid,
        enabled
    ) VALUES (
        v_system_id,
        p_test_environment,
        p_test_type,
        'grafana',
        p_grafana,
        p_dashboard_label,
        p_dashboard_id,
        p_dashboard_uid,
        p_panel,
        p_generic_check_id,
        p_valid,
        true
    )
    RETURNING id INTO v_benchmark_id;
    
    RETURN v_benchmark_id;
END;
$$;


--
-- Name: percentile_agg_finalfunc(double precision[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.percentile_agg_finalfunc(vals double precision[]) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
  result JSONB;
BEGIN
  -- Return NULL if no values
  IF vals IS NULL OR array_length(vals, 1) IS NULL THEN
    RETURN NULL;
  END IF;

  -- Calculate percentiles using PERCENTILE_CONT
  -- Using unnest to convert array to rows, then aggregate back
  SELECT jsonb_build_object(
    'p50', PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY val),
    'p90', PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY val),
    'p95', PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY val),
    'p99', PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY val)
  ) INTO result
  FROM unnest(vals) AS val;

  RETURN result;
END;
$$;


--
-- Name: update_deep_links_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_deep_links_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_generic_deep_links_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_generic_deep_links_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_graph_preset_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_graph_preset_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.updated_at = CURRENT_TIMESTAMP;
        RETURN NEW;
      END;
      $$;


--
-- Name: update_graph_presets_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_graph_presets_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


--
-- Name: update_tracing_instance_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_tracing_instance_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.updated_at = CURRENT_TIMESTAMP;
        RETURN NEW;
      END;
      $$;


--
-- Name: update_tracing_service_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_tracing_service_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.updated_at = CURRENT_TIMESTAMP;
        RETURN NEW;
      END;
      $$;


--
-- Name: update_transaction_apdex_threshold_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_transaction_apdex_threshold_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.updated_at = CURRENT_TIMESTAMP;
        RETURN NEW;
      END;
      $$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_workload_apdex_threshold_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_workload_apdex_threshold_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.updated_at = CURRENT_TIMESTAMP;
        RETURN NEW;
      END;
      $$;


--
-- Name: update_workload_transaction_apdex_threshold_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_workload_transaction_apdex_threshold_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.updated_at = CURRENT_TIMESTAMP;
        RETURN NEW;
      END;
      $$;


--
-- Name: validate_benchmark_configuration(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_benchmark_configuration() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Configuration must be a valid JSON object
    IF NEW.configuration IS NULL OR jsonb_typeof(NEW.configuration) != 'object' THEN
        RAISE EXCEPTION 'Configuration must be a valid JSON object';
    END IF;
    
    -- Source-specific validation
    IF NEW.source = 'grafana' THEN
        -- Grafana-specific validation
        IF NEW.configuration->>'dashboardUid' IS NULL THEN
            RAISE EXCEPTION 'Grafana configuration must have a dashboardUid';
        END IF;
        
        IF NEW.configuration->>'id' IS NULL THEN
            RAISE EXCEPTION 'Grafana configuration must have an id';
        END IF;
    ELSIF NEW.source = 'dynatrace' THEN
        -- Dynatrace-specific validation (no additional requirements)
    ELSIF NEW.source IN ('timescaledb', 'influxdb') THEN
        -- Time-series database validation
        IF NEW.configuration->>'query' IS NULL THEN
            RAISE EXCEPTION 'Time-series database configuration must have a query';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: api_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_keys (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    api_key character varying NOT NULL,
    description character varying NOT NULL,
    roles text[] DEFAULT '{}'::text[] NOT NULL,
    valid_until timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used timestamp with time zone,
    organization_id uuid,
    created_by character varying(255),
    updated_by character varying(255),
    team_id uuid
);

ALTER TABLE ONLY public.api_keys FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN api_keys.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.api_keys.organization_id IS 'Organization this API key belongs to. NULL only allowed for legacy keys (global admin only).';


--
-- Name: COLUMN api_keys.created_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.api_keys.created_by IS 'User ID (Keycloak sub) who created this API key';


--
-- Name: COLUMN api_keys.updated_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.api_keys.updated_by IS 'User ID (Keycloak sub) who last modified this API key';


--
-- Name: application_dashboards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.application_dashboards (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    system_under_test_id uuid NOT NULL,
    test_environment character varying(255) NOT NULL,
    grafana_instance_id uuid NOT NULL,
    grafana_dashboard_id uuid NOT NULL,
    dashboard_name character varying(255) NOT NULL,
    dashboard_id integer,
    dashboard_uid character varying(100),
    dashboard_label character varying(255) NOT NULL,
    tags text[],
    template_dashboard_uid character varying(100),
    variables jsonb,
    replaced_templating_variables jsonb,
    snapshot_timeout integer DEFAULT 4 NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.application_dashboards FORCE ROW LEVEL SECURITY;


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    user_id text NOT NULL,
    user_email text,
    action text NOT NULL,
    resource_type text NOT NULL,
    resource_id text,
    organization_id uuid,
    ip_address text,
    user_agent text,
    changes jsonb,
    metadata jsonb,
    error_message text,
    resource_name character varying(255),
    success boolean DEFAULT true
);


--
-- Name: awr_analysis; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.awr_analysis (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    awr_report_id uuid NOT NULL,
    baseline_report_id uuid,
    analysis_type character varying(20) DEFAULT 'single'::character varying NOT NULL,
    analysis_version character varying(50),
    insights jsonb,
    severity_summary jsonb,
    analyzed_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: awr_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.awr_reports (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    test_run_id uuid NOT NULL,
    file_name character varying(255) NOT NULL,
    file_size integer NOT NULL,
    file_type character varying(10) DEFAULT 'html'::character varying NOT NULL,
    raw_content text,
    raw_content_url character varying(500),
    db_name character varying(255),
    db_id character varying(255),
    instance_name character varying(255),
    db_edition character varying(50),
    db_release character varying(100),
    is_rac boolean,
    is_cdb boolean,
    host_name character varying(255),
    platform character varying(255),
    cpus integer,
    cores integer,
    sockets integer,
    memory_gb numeric(10,2),
    snap_id_begin integer,
    snap_id_end integer,
    begin_time timestamp with time zone,
    end_time timestamp with time zone,
    elapsed_minutes numeric(10,2),
    db_time_minutes numeric(10,2),
    sessions_begin integer,
    sessions_end integer,
    parsed_data jsonb,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL,
    uploaded_by character varying(255) NOT NULL,
    parsed_at timestamp with time zone,
    parse_status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    parse_error text,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: benchmarks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.benchmarks (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    system_under_test_id uuid NOT NULL,
    test_environment character varying(255) NOT NULL,
    workload character varying(255) NOT NULL,
    source character varying(50) DEFAULT 'grafana'::character varying NOT NULL,
    grafana_instance character varying(255),
    dashboard_label character varying(500),
    dashboard_id integer,
    dashboard_uid character varying(255),
    application_dashboard_id uuid,
    generic_check_id character varying(500),
    configuration jsonb DEFAULT '{}'::jsonb NOT NULL,
    config_title character varying,
    config_id character varying,
    config_type character varying,
    evaluate_type character varying,
    requirement_operator character varying,
    requirement_value numeric,
    enabled boolean DEFAULT true NOT NULL,
    valid boolean DEFAULT true NOT NULL,
    description text,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    average_all boolean DEFAULT false NOT NULL,
    match_pattern text,
    validate_with_default_if_no_data boolean DEFAULT false NOT NULL,
    validate_with_default_if_no_data_value numeric,
    exclude_ramp_up_time boolean DEFAULT true NOT NULL,
    panel_title character varying(255),
    metric_unit character varying(50),
    baseline_test_run_id character varying(255),
    alert_on_breach boolean DEFAULT false NOT NULL,
    alert_channels text[] DEFAULT '{}'::text[] NOT NULL,
    benchmark_type character varying(20) DEFAULT 'metric'::character varying NOT NULL,
    transaction_name character varying(255),
    apdex_threshold_ms integer,
    min_apdex_score numeric(4,3),
    include_failed_requests boolean DEFAULT false NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by character varying(255),
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid
);

ALTER TABLE ONLY public.benchmarks FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN benchmarks.benchmark_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.benchmarks.benchmark_type IS 'Type of benchmark: metric (Grafana-based) or apdex (transaction response time based)';


--
-- Name: COLUMN benchmarks.transaction_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.benchmarks.transaction_name IS 'Transaction name for Apdex SLOs. NULL means workload-level aggregate.';


--
-- Name: COLUMN benchmarks.apdex_threshold_ms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.benchmarks.apdex_threshold_ms IS 'Apdex T threshold in milliseconds. Satisfied: <=T, Tolerating: T<x<=4T, Frustrated: >4T';


--
-- Name: COLUMN benchmarks.min_apdex_score; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.benchmarks.min_apdex_score IS 'Minimum required Apdex score (0.0-1.0). Benchmark passes if calculated >= this value.';


--
-- Name: COLUMN benchmarks.include_failed_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.benchmarks.include_failed_requests IS 'Whether to include failed requests in Apdex calculation (default: false)';


--
-- Name: grafana_dashboards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grafana_dashboards (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    grafana_instance_id uuid NOT NULL,
    grafana_id integer NOT NULL,
    datasource_type character varying,
    uid character varying(255) NOT NULL,
    slug character varying(255),
    name character varying(255) NOT NULL,
    uri text,
    templating_variables jsonb,
    panels jsonb NOT NULL,
    variables jsonb,
    tags text[],
    used_by_sut text[],
    template_dashboard_uid character varying(255),
    template_profile character varying(255),
    template_test_run_variables jsonb,
    template_create_date timestamp with time zone,
    application_dashboard_variables jsonb,
    grafana_json jsonb,
    updated timestamp with time zone,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.grafana_dashboards FORCE ROW LEVEL SECURITY;


--
-- Name: grafana_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grafana_instances (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    label character varying(255) NOT NULL,
    client_url text NOT NULL,
    server_url text,
    org_id character varying(255) NOT NULL,
    api_key text,
    username character varying(255),
    password text,
    snapshot_instance boolean,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.grafana_instances FORCE ROW LEVEL SECURITY;


--
-- Name: systems_under_test; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.systems_under_test (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    team_id uuid,
    name character varying(255) NOT NULL,
    description text NOT NULL,
    tracing_service character varying(255),
    pyroscope_instance_id uuid,
    pyroscope_configurations jsonb DEFAULT '[]'::jsonb,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by character varying(255),
    updated_by character varying(255),
    organization_id uuid
);

ALTER TABLE ONLY public.systems_under_test FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN systems_under_test.created_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.systems_under_test.created_by IS 'User ID (Keycloak sub) or API key identifier (api-key:{id}) who created this system';


--
-- Name: COLUMN systems_under_test.updated_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.systems_under_test.updated_by IS 'User ID (Keycloak sub) or API key identifier (api-key:{id}) who last modified this system';


--
-- Name: COLUMN systems_under_test.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.systems_under_test.organization_id IS 'Organization this system belongs to. Nullable for backward compatibility. Will be required after data migration.';


--
-- Name: benchmarks_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.benchmarks_view AS
 SELECT b.id,
    b.system_under_test_id,
    b.test_environment,
    b.workload AS test_type,
    b.source,
    b.grafana_instance,
    b.dashboard_label,
    b.dashboard_id,
    b.dashboard_uid,
    b.application_dashboard_id,
    b.generic_check_id,
    b.configuration,
    b.config_title,
    b.config_id,
    b.config_type,
    b.evaluate_type,
    b.requirement_operator,
    b.requirement_value,
    b.enabled,
    b.valid,
    b.description,
    b.tags,
    b.average_all,
    b.match_pattern,
    b.validate_with_default_if_no_data,
    b.validate_with_default_if_no_data_value,
    b.exclude_ramp_up_time,
    b.panel_title AS metric_name,
    b.metric_unit,
    b.baseline_test_run_id,
    b.alert_on_breach,
    b.alert_channels,
    b.metadata,
    b.created_at,
    b.updated_at,
    b.created_by,
    b.updated_by,
    sut.name AS system_name,
    sut.description AS system_description,
    gi.label AS grafana_instance_label,
    gi.client_url AS grafana_url,
    gd.name AS grafana_dashboard_name,
    gd.tags AS dashboard_tags,
        CASE
            WHEN (((b.requirement_operator)::text = 'lt'::text) AND (b.requirement_value IS NOT NULL)) THEN ((('Value must be less than '::text || b.requirement_value) || ' '::text) || (COALESCE(b.metric_unit, ''::character varying))::text)
            WHEN (((b.requirement_operator)::text = 'gt'::text) AND (b.requirement_value IS NOT NULL)) THEN ((('Value must be greater than '::text || b.requirement_value) || ' '::text) || (COALESCE(b.metric_unit, ''::character varying))::text)
            WHEN (((b.requirement_operator)::text = 'lte'::text) AND (b.requirement_value IS NOT NULL)) THEN ((('Value must be less than or equal to '::text || b.requirement_value) || ' '::text) || (COALESCE(b.metric_unit, ''::character varying))::text)
            WHEN (((b.requirement_operator)::text = 'gte'::text) AND (b.requirement_value IS NOT NULL)) THEN ((('Value must be greater than or equal to '::text || b.requirement_value) || ' '::text) || (COALESCE(b.metric_unit, ''::character varying))::text)
            WHEN (((b.requirement_operator)::text = 'eq'::text) AND (b.requirement_value IS NOT NULL)) THEN ((('Value must equal '::text || b.requirement_value) || ' '::text) || (COALESCE(b.metric_unit, ''::character varying))::text)
            WHEN (((b.requirement_operator)::text = 'ne'::text) AND (b.requirement_value IS NOT NULL)) THEN ((('Value must not equal '::text || b.requirement_value) || ' '::text) || (COALESCE(b.metric_unit, ''::character varying))::text)
            ELSE 'No requirement defined'::text
        END AS requirement_description
   FROM (((public.benchmarks b
     LEFT JOIN public.systems_under_test sut ON ((b.system_under_test_id = sut.id)))
     LEFT JOIN public.grafana_instances gi ON (((b.grafana_instance)::text = (gi.label)::text)))
     LEFT JOIN public.grafana_dashboards gd ON ((((b.dashboard_uid)::text = (gd.uid)::text) AND (gd.grafana_instance_id = gi.id))));


--
-- Name: check_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.check_results (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    system_under_test_id uuid NOT NULL,
    test_environment character varying(255) NOT NULL,
    workload character varying(255) NOT NULL,
    test_run_id character varying(255) NOT NULL,
    source character varying(50) DEFAULT 'grafana'::character varying NOT NULL,
    grafana_instance character varying(255),
    dashboard_label character varying(500),
    dashboard_uid character varying(255),
    panel_title character varying(500),
    panel_id integer,
    panel_type character varying(100),
    panel_description text,
    panel_y_axes_format character varying(100),
    dynatrace_entity_id character varying(255),
    dynatrace_metric_key character varying(255),
    dynatrace_dimension_filters jsonb DEFAULT '{}'::jsonb,
    metric_name character varying(255),
    metric_unit character varying(50),
    generic_check_id character varying(500),
    benchmark_id character varying(255) NOT NULL,
    status character varying(50) NOT NULL,
    message text,
    average_all boolean DEFAULT false NOT NULL,
    evaluate_type character varying(100) NOT NULL,
    exclude_ramp_up_time boolean DEFAULT true NOT NULL,
    ramp_up integer,
    match_pattern text,
    requirement jsonb DEFAULT '{}'::jsonb,
    benchmark jsonb DEFAULT '{}'::jsonb,
    panel_average numeric,
    meets_requirement boolean,
    is_artificial boolean DEFAULT false,
    targets jsonb DEFAULT '[]'::jsonb,
    validate_with_default_if_no_data boolean DEFAULT false,
    validate_with_default_if_no_data_value numeric,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by character varying(255),
    updated_by character varying(255),
    tags text[],
    application_dashboard_id uuid,
    organization_id uuid,
    team_id uuid,
    CONSTRAINT check_results_source_check CHECK (((source)::text = ANY ((ARRAY['grafana'::character varying, 'dynatrace'::character varying, 'timescaledb'::character varying, 'influxdb'::character varying, 'prometheus'::character varying, 'custom'::character varying])::text[])))
);


--
-- Name: TABLE check_results; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.check_results IS 'Benchmark check results from various sources (Grafana, Dynatrace, InfluxDB, etc.)';


--
-- Name: compare_filter_presets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.compare_filter_presets (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    preset_type character varying(20) DEFAULT 'generic'::character varying NOT NULL,
    series_search_text character varying(255),
    show_percentiles boolean DEFAULT false NOT NULL,
    panel_id integer,
    panel_title character varying(255),
    baseline_test_run_id character varying(255),
    is_global boolean DEFAULT false NOT NULL,
    application_dashboard_id uuid,
    source character varying(20) DEFAULT 'grafana'::character varying,
    dashboard_label character varying(255),
    series_config jsonb,
    created_for_test_run_id character varying(255),
    created_by character varying(255),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    updated_by character varying(255)
);

ALTER TABLE ONLY public.compare_filter_presets FORCE ROW LEVEL SECURITY;


--
-- Name: configuration; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.configuration (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    type character varying(255) NOT NULL,
    key character varying(255) NOT NULL,
    value text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: data_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_sources (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    source_type character varying(100) NOT NULL,
    instance_name character varying(255) NOT NULL,
    connection_config jsonb NOT NULL,
    supports_real_time boolean DEFAULT false,
    supports_historical boolean DEFAULT true,
    query_rate_limit integer,
    is_active boolean DEFAULT true,
    last_health_check timestamp with time zone,
    health_status character varying(50),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: deep_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deep_links (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    system_under_test_id uuid NOT NULL,
    test_environment character varying(255) NOT NULL,
    workload character varying(255) NOT NULL,
    name character varying(500) NOT NULL,
    url text NOT NULL,
    template_deep_link_id uuid,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.deep_links FORCE ROW LEVEL SECURITY;


--
-- Name: ds_adapt_conclusion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_adapt_conclusion (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    test_run_id character varying(255) NOT NULL,
    control_group_id character varying(255),
    regressions uuid[],
    improvements uuid[],
    differences uuid[],
    tracked_regressions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    conclusion character varying(50) NOT NULL,
    details jsonb NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_adapt_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_adapt_results (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    test_run_id character varying(255) NOT NULL,
    control_group_id character varying(255) NOT NULL,
    application_dashboard_id uuid NOT NULL,
    panel_id integer NOT NULL,
    metric_name character varying(500) NOT NULL,
    dashboard_uid character varying(255) NOT NULL,
    dashboard_label character varying(500) NOT NULL,
    panel_title character varying(500) NOT NULL,
    unit character varying(100),
    test_run_start timestamp with time zone NOT NULL,
    benchmark_ids text[],
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    mean jsonb,
    min jsonb,
    max jsonb,
    std jsonb,
    median jsonb,
    q10 jsonb,
    q25 jsonb,
    q75 jsonb,
    q90 jsonb,
    q95 jsonb,
    q99 jsonb,
    last_value jsonb,
    n jsonb,
    n_missing jsonb,
    n_non_zero jsonb,
    iqr jsonb,
    idr jsonb,
    is_constant jsonb,
    all_missing jsonb,
    exists_data jsonb,
    pct_missing jsonb,
    compare_config jsonb NOT NULL,
    metric_classification jsonb,
    statistic jsonb NOT NULL,
    conditions jsonb NOT NULL,
    thresholds jsonb NOT NULL,
    checks jsonb NOT NULL,
    conclusion jsonb NOT NULL,
    uses_default_value boolean DEFAULT false NOT NULL,
    default_value numeric,
    config_hash_used character varying(32),
    is_stale boolean DEFAULT false NOT NULL,
    stale_reason character varying(255),
    stale_at timestamp with time zone,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_adapt_tracked_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_adapt_tracked_results (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    test_run_id character varying NOT NULL,
    control_group_id character varying NOT NULL,
    tracked_test_run_id character varying NOT NULL,
    tracked_difference_id character varying,
    application_dashboard_id uuid NOT NULL,
    panel_id integer NOT NULL,
    metric_name character varying NOT NULL,
    dashboard_uid character varying,
    dashboard_label character varying,
    panel_title character varying,
    unit character varying,
    benchmark_ids text[],
    test_run_start timestamp with time zone NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    mean jsonb,
    median jsonb,
    min_value jsonb,
    max_value jsonb,
    std_dev jsonb,
    q10 jsonb,
    q25 jsonb,
    q75 jsonb,
    q90 jsonb,
    q95 jsonb,
    q99 jsonb,
    iqr jsonb,
    idr jsonb,
    count jsonb,
    n_missing jsonb,
    n_non_zero jsonb,
    pct_missing jsonb,
    is_constant jsonb,
    all_missing jsonb,
    last_value jsonb,
    exists_flags jsonb,
    uses_default_value boolean DEFAULT false NOT NULL,
    default_value numeric,
    compare_config jsonb,
    metric_classification jsonb,
    statistic jsonb,
    conditions jsonb,
    thresholds jsonb,
    checks jsonb,
    conclusion jsonb,
    tracked_conclusion jsonb,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_change_points; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_change_points (
    id integer NOT NULL,
    system_under_test_id character varying(255) NOT NULL,
    workload character varying(255) NOT NULL,
    test_environment character varying(255) NOT NULL,
    test_run_id character varying(255) NOT NULL,
    application_dashboard_id uuid,
    panel_title character varying(500),
    dashboard_label character varying(255),
    dashboard_uid character varying(255),
    panel_id integer,
    metric_name character varying(255),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_change_points_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ds_change_points_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ds_change_points_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ds_change_points_id_seq OWNED BY public.ds_change_points.id;


--
-- Name: ds_compare_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_compare_config (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    application_dashboard_id uuid NOT NULL,
    panel_id integer NOT NULL,
    config_data jsonb NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    metric_name character varying(255),
    system_under_test_id uuid NOT NULL,
    test_environment character varying(255) NOT NULL,
    workload character varying(255) NOT NULL,
    config_hash character varying(32),
    last_modified_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_control_group_statistics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_control_group_statistics (
    id integer NOT NULL,
    control_group_id character varying(255) NOT NULL,
    application_dashboard_id uuid NOT NULL,
    panel_id integer NOT NULL,
    metric_name character varying(255),
    mean double precision,
    median double precision,
    min_value double precision,
    max_value double precision,
    std_dev double precision,
    last_value double precision,
    count integer NOT NULL,
    n_missing integer DEFAULT 0 NOT NULL,
    n_non_zero integer DEFAULT 0 NOT NULL,
    q10 double precision,
    q25 double precision,
    q75 double precision,
    q90 double precision,
    q95 double precision,
    q99 double precision,
    is_constant boolean DEFAULT false NOT NULL,
    all_missing boolean DEFAULT false NOT NULL,
    pct_missing double precision,
    iqr double precision,
    idr double precision,
    unit character varying(50),
    timestep double precision,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    test_run_id character varying(255),
    dashboard_uid character varying(255),
    dashboard_label character varying(500),
    panel_title character varying(500),
    benchmark_ids character varying[],
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_control_group_statistics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ds_control_group_statistics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ds_control_group_statistics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ds_control_group_statistics_id_seq OWNED BY public.ds_control_group_statistics.id;


--
-- Name: ds_control_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_control_groups (
    id integer NOT NULL,
    control_group_id character varying(255) NOT NULL,
    system_under_test_id character varying(255),
    workload character varying(255),
    test_environment character varying(255),
    n_test_runs integer DEFAULT 0 NOT NULL,
    test_runs text[],
    first_datetime timestamp with time zone,
    last_datetime timestamp with time zone,
    metric_filters jsonb DEFAULT '{}'::jsonb NOT NULL,
    change_point jsonb,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_control_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ds_control_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ds_control_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ds_control_groups_id_seq OWNED BY public.ds_control_groups.id;


--
-- Name: ds_metric_classification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_metric_classification (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    system_under_test_id uuid,
    test_environment character varying(255),
    workload character varying(255),
    dashboard_uid character varying(255),
    dashboard_label character varying(255),
    application_dashboard_id uuid,
    panel_id integer,
    panel_title character varying(500),
    metric_name character varying(255),
    regex boolean DEFAULT false NOT NULL,
    higher_is_better boolean,
    metric_classification character varying(255),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_metric_collection_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_metric_collection_status (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    test_run_id character varying(255) NOT NULL,
    source_type character varying(50) NOT NULL,
    source_id character varying(255),
    collected_ranges jsonb DEFAULT '[]'::jsonb NOT NULL,
    failed_ranges jsonb DEFAULT '[]'::jsonb NOT NULL,
    last_collected_at timestamp with time zone,
    is_complete boolean DEFAULT false NOT NULL,
    total_data_points integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: TABLE ds_metric_collection_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ds_metric_collection_status IS 'Tracks metric collection progress from various sources (Grafana, Dynatrace, performance tests) for data science analysis';


--
-- Name: COLUMN ds_metric_collection_status.test_run_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ds_metric_collection_status.test_run_id IS 'Test run identifier (supports both UUID and custom test_run_id)';


--
-- Name: COLUMN ds_metric_collection_status.source_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ds_metric_collection_status.source_type IS 'Source type: grafana, dynatrace, or performance_test';


--
-- Name: COLUMN ds_metric_collection_status.source_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ds_metric_collection_status.source_id IS 'Optional source identifier (e.g., Grafana/Dynatrace instance ID)';


--
-- Name: COLUMN ds_metric_collection_status.collected_ranges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ds_metric_collection_status.collected_ranges IS 'Array of successfully collected time ranges as JSON objects with start/end timestamps';


--
-- Name: COLUMN ds_metric_collection_status.failed_ranges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ds_metric_collection_status.failed_ranges IS 'Array of failed time ranges as JSON objects with start/end timestamps and error details';


--
-- Name: COLUMN ds_metric_collection_status.last_collected_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ds_metric_collection_status.last_collected_at IS 'Timestamp of last successful collection attempt';


--
-- Name: COLUMN ds_metric_collection_status.is_complete; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ds_metric_collection_status.is_complete IS 'Indicates if all metrics have been collected for this source';


--
-- Name: COLUMN ds_metric_collection_status.total_data_points; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ds_metric_collection_status.total_data_points IS 'Total number of data points collected from this source';


--
-- Name: ds_metric_statistics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_metric_statistics (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    test_run_id character varying(255) NOT NULL,
    application_dashboard_id uuid NOT NULL,
    panel_id integer NOT NULL,
    benchmark_id uuid,
    count bigint,
    mean double precision,
    median double precision,
    min_value double precision,
    max_value double precision,
    std_dev double precision,
    percentiles jsonb,
    iqr double precision,
    idr double precision,
    missing_percentage double precision,
    constant_value boolean,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    metric_name character varying(255),
    test_run_start timestamp with time zone,
    dashboard_uid character varying(255),
    dashboard_label character varying(255),
    panel_title character varying(500),
    unit character varying(50),
    q10 double precision,
    q25 double precision,
    q75 double precision,
    q90 double precision,
    q95 double precision,
    q99 double precision,
    is_constant boolean,
    all_missing boolean,
    pct_missing double precision,
    last_value double precision,
    n_missing integer,
    n_non_zero integer,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_metrics (
    test_run_id character varying(255) NOT NULL,
    application_dashboard_id uuid NOT NULL,
    dashboard_uid character varying(255) NOT NULL,
    panel_id integer NOT NULL,
    "time" timestamp with time zone NOT NULL,
    metric_name character varying(255) NOT NULL,
    panel_title character varying(500),
    dashboard_label character varying(255),
    benchmark_ids text[],
    errors jsonb,
    timestep double precision,
    ramp_up boolean,
    value double precision,
    unit character varying(50),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_panels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_panels (
    id integer NOT NULL,
    test_run_id character varying NOT NULL,
    application_dashboard_id uuid NOT NULL,
    dashboard_uid character varying(255),
    panel_id integer,
    panel_title character varying(500),
    dashboard_label character varying,
    benchmark_ids text[],
    panel jsonb,
    query_variables jsonb,
    datasource_type character varying,
    requests jsonb,
    errors jsonb,
    warnings jsonb,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_panels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ds_panels_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ds_panels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ds_panels_id_seq OWNED BY public.ds_panels.id;


--
-- Name: ds_queries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_queries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    source_type character varying(100) NOT NULL,
    source_instance character varying(255) NOT NULL,
    query_name character varying(255),
    query_hash character varying(64) NOT NULL,
    query_definition jsonb NOT NULL,
    query_parameters jsonb,
    target_reference jsonb,
    expected_metrics text[],
    execution_timeout integer DEFAULT 120,
    retry_count integer DEFAULT 3,
    avg_execution_time_ms integer,
    last_execution_time timestamp with time zone,
    success_rate numeric(5,2),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_query_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_query_executions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    query_id uuid NOT NULL,
    test_run_id uuid,
    executed_at timestamp with time zone DEFAULT now(),
    execution_parameters jsonb,
    status character varying(50) NOT NULL,
    execution_time_ms integer,
    rows_returned integer,
    data_points_collected integer,
    error_code character varying(100),
    error_message text,
    retry_attempt integer DEFAULT 0,
    metrics_stored_count integer,
    created_at timestamp with time zone DEFAULT now(),
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: ds_tracked_differences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ds_tracked_differences (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    test_run_id uuid NOT NULL,
    application_dashboard_id uuid NOT NULL,
    panel_id integer NOT NULL,
    benchmark_id uuid,
    difference_data jsonb NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: dynatrace_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dynatrace_configs (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    host character varying(500) NOT NULL,
    api_token text NOT NULL,
    dynatrace_type character varying(20) DEFAULT 'saas'::character varying NOT NULL,
    label character varying(255) NOT NULL,
    platform_api_token text,
    perfana_test_run_id_attribute character varying(255),
    perfana_request_name_attribute character varying(255),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.dynatrace_configs FORCE ROW LEVEL SECURITY;


--
-- Name: dynatrace_entity_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dynatrace_entity_mappings (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    dynatrace_config_id uuid NOT NULL,
    system_under_test_id uuid NOT NULL,
    test_environment character varying(255),
    workload character varying(255),
    entity_id character varying(255) NOT NULL,
    entity_display_name character varying(500) NOT NULL,
    entity_type character varying(100) NOT NULL,
    level character varying(50) NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.dynatrace_entity_mappings FORCE ROW LEVEL SECURITY;


--
-- Name: dynatrace_queries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dynatrace_queries (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    dynatrace_config_id uuid NOT NULL,
    system_under_test_id uuid NOT NULL,
    test_environment character varying(255) NOT NULL,
    workload character varying(255) NOT NULL,
    dashboard_label character varying(500) NOT NULL,
    application_dashboard_id uuid,
    panel_title character varying(500) NOT NULL,
    panel_id integer NOT NULL,
    query text NOT NULL,
    match_metric_pattern character varying(500),
    omit_group_by_variable_from_metric_name text[] DEFAULT '{}'::text[] NOT NULL,
    template_variables jsonb DEFAULT '{}'::jsonb NOT NULL,
    metric_unit character varying(50),
    metric_name character varying(255),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.dynatrace_queries FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN dynatrace_queries.metric_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.dynatrace_queries.metric_name IS 'Explicit metric name for storage (e.g., "CPU Usage", "Memory Usage"). Used instead of deriving from DQL field names.';


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    system_under_test_id uuid NOT NULL,
    test_environment character varying(255) NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    tags text[],
    grafana_annotation_ids jsonb DEFAULT '{}'::jsonb,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.events FORCE ROW LEVEL SECURITY;


--
-- Name: expected_config_changes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expected_config_changes (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    system_under_test_id uuid NOT NULL,
    test_environment character varying(255) NOT NULL,
    workload character varying(255) NOT NULL,
    config_key character varying(500) NOT NULL,
    expected_value text,
    description text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.expected_config_changes FORCE ROW LEVEL SECURITY;


--
-- Name: generated_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.generated_reports (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    test_run_id uuid NOT NULL,
    template_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    generated_by character varying(255) NOT NULL,
    html_content text,
    html_generated_at timestamp with time zone,
    share_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    share_enabled boolean DEFAULT false NOT NULL,
    share_view_count integer DEFAULT 0 NOT NULL,
    last_shared_at timestamp with time zone,
    file_path character varying(1024),
    pdf_data bytea,
    file_size bigint,
    mime_type character varying(100) DEFAULT 'application/pdf'::character varying NOT NULL,
    file_metadata jsonb,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    error_code character varying(100),
    error_message text,
    job_id character varying(100),
    retry_count integer DEFAULT 0 NOT NULL,
    max_retries integer DEFAULT 3 NOT NULL,
    download_count integer DEFAULT 0 NOT NULL,
    last_downloaded_at timestamp with time zone,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.generated_reports FORCE ROW LEVEL SECURITY;


--
-- Name: generic_deep_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.generic_deep_links (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    profile character varying(255) NOT NULL,
    name character varying(500) NOT NULL,
    url text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.generic_deep_links FORCE ROW LEVEL SECURITY;


--
-- Name: graph_presets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.graph_presets (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    test_run_id character varying(255),
    user_id character varying(255) NOT NULL,
    series_config jsonb NOT NULL,
    chart_options jsonb,
    is_global boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.graph_presets FORCE ROW LEVEL SECURITY;


--
-- Name: licenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.licenses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying(255) NOT NULL,
    license_type integer,
    customer_name character varying(255),
    public_key text,
    valid_until timestamp with time zone,
    all_ok boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.migrations (
    id integer NOT NULL,
    "timestamp" bigint NOT NULL,
    name character varying NOT NULL
);


--
-- Name: migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.migrations_id_seq OWNED BY public.migrations.id;


--
-- Name: notification_channels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_channels (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    system_under_test_id uuid NOT NULL,
    type character varying(20) NOT NULL,
    name character varying(255) NOT NULL,
    webhook_url text NOT NULL,
    notify_on_finished boolean DEFAULT true NOT NULL,
    notify_on_failed_only boolean DEFAULT false NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.notification_channels FORCE ROW LEVEL SECURITY;


--
-- Name: organization_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_members (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    organization_id uuid NOT NULL,
    user_id character varying(255) NOT NULL,
    roles jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: pending_ds_compare_config_changes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pending_ds_compare_config_changes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ds_compare_config_id uuid NOT NULL,
    pending_changes jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: profile_benchmarks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profile_benchmarks (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    profile_id uuid NOT NULL,
    profile_dashboard_id uuid NOT NULL,
    workload_pattern character varying(500) DEFAULT '.*'::character varying NOT NULL,
    source character varying(50) DEFAULT 'grafana'::character varying NOT NULL,
    grafana_instance character varying(255),
    dashboard_uid character varying(255),
    panel_id integer,
    panel_title character varying(255),
    panel_type character varying(50),
    panel_description character varying(255),
    evaluate_type character varying(50),
    metric_unit character varying(50),
    requirement_operator character varying(50),
    requirement_value numeric,
    exclude_ramp_up_time boolean DEFAULT true NOT NULL,
    average_all boolean DEFAULT false NOT NULL,
    match_pattern text,
    validate_with_default_if_no_data boolean DEFAULT false NOT NULL,
    validate_with_default_if_no_data_value numeric,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_only boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: profile_grafana_dashboards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profile_grafana_dashboards (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    profile character varying(255) NOT NULL,
    dashboard_name character varying(255) NOT NULL,
    dashboard_uid character varying(100) NOT NULL,
    grafana_label character varying(255) DEFAULT 'Default'::character varying NOT NULL,
    create_separate_dashboard_for_variable character varying(255),
    set_hardcoded_value_for_variables jsonb,
    match_regex_for_variables jsonb,
    read_only boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    tags text[],
    read_only boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.profiles FORCE ROW LEVEL SECURITY;


--
-- Name: pyroscope_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pyroscope_instances (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    label character varying(255) NOT NULL,
    pyroscope_url text NOT NULL,
    backend_url text,
    pyroscope_stand_alone boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.pyroscope_instances FORCE ROW LEVEL SECURITY;


--
-- Name: report_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.report_templates (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    created_by character varying(255) NOT NULL,
    system_id character varying(255) NOT NULL,
    test_environment character varying(255) NOT NULL,
    workload character varying(255) NOT NULL,
    sections jsonb DEFAULT '[]'::jsonb NOT NULL,
    styling jsonb,
    is_default boolean DEFAULT false NOT NULL,
    is_adhoc boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    updated_by character varying(255)
);

ALTER TABLE ONLY public.report_templates FORCE ROW LEVEL SECURITY;


--
-- Name: requests_error; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.requests_error (
    "time" timestamp with time zone NOT NULL,
    test_run_id text NOT NULL,
    system_under_test text,
    test_environment text,
    location text,
    node_name text NOT NULL,
    transaction_name text NOT NULL,
    sampler_name text NOT NULL,
    response_code text,
    response_time integer,
    connection_time integer,
    url text,
    assertions text,
    response_message text,
    request_headers text,
    response_headers text,
    response_data text,
    random_id integer,
    scenario_name text,
    url_hash text
);


--
-- Name: requests_raw; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.requests_raw (
    "time" timestamp with time zone NOT NULL,
    test_run_id text NOT NULL,
    system_under_test text,
    test_environment text,
    location text,
    transaction_name text,
    sampler_name text NOT NULL,
    success boolean NOT NULL,
    request_size integer,
    response_size integer,
    response_code text,
    response_connect_time integer,
    response_latency integer,
    response_time integer,
    scenario_name text,
    url_hash text
);


--
-- Name: system_under_test_test_environments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_under_test_test_environments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    system_under_test_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    tracing_service character varying(255),
    pyroscope_application character varying(255),
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE system_under_test_test_environments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.system_under_test_test_environments IS 'Test environments for each system under test (e.g., dev, acc, prod)';


--
-- Name: system_under_test_workloads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_under_test_workloads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    system_under_test_test_environment_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    config jsonb,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE system_under_test_workloads; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.system_under_test_workloads IS 'Workloads/test types for each environment (e.g., load, stress, endurance)';


--
-- Name: team_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_members (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    team_id uuid NOT NULL,
    user_id character varying(255) NOT NULL,
    roles jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    restrict_to_team_members boolean DEFAULT false NOT NULL
);


--
-- Name: test_run_alerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.test_run_alerts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    test_run_id uuid NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    level character varying(50) NOT NULL,
    message text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: test_run_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.test_run_configs (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    test_run_id uuid,
    key character varying NOT NULL,
    value text,
    tags text[],
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    test_run_id_string character varying,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: test_run_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.test_run_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    test_run_id uuid NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    event_data jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: test_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.test_runs (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    system_under_test_id uuid NOT NULL,
    test_environment character varying(255) NOT NULL,
    workload character varying(255) NOT NULL,
    test_run_id character varying(255) NOT NULL,
    start_time timestamp with time zone,
    end_time timestamp with time zone,
    duration integer,
    planned_duration integer,
    ramp_up integer,
    completed boolean DEFAULT false,
    abort boolean DEFAULT false,
    is_stale boolean DEFAULT false,
    stale_detected_at timestamp with time zone,
    status jsonb,
    consolidated_result jsonb,
    annotations text[],
    tags text[],
    application_release character varying(255),
    ci_build_results_url character varying(255),
    expires timestamp with time zone,
    expired boolean DEFAULT false,
    valid boolean DEFAULT true,
    reasons_not_valid text[],
    adapt_config jsonb,
    variables jsonb,
    deep_links jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.test_runs FORCE ROW LEVEL SECURITY;


--
-- Name: tracing_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tracing_instances (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    label character varying(255) NOT NULL,
    tracing_url text NOT NULL,
    tracing_api_url text,
    tracing_ui public.tracing_instances_tracing_ui_enum NOT NULL,
    tracing_iframe_allowed boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.tracing_instances FORCE ROW LEVEL SECURITY;


--
-- Name: tracing_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tracing_services (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    system_under_test_id uuid NOT NULL,
    test_environment character varying,
    workload character varying,
    tracing_instance_id uuid NOT NULL,
    service_names text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.tracing_services FORCE ROW LEVEL SECURITY;


--
-- Name: transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transactions (
    "time" timestamp with time zone NOT NULL,
    test_run_id text NOT NULL,
    system_under_test text,
    test_environment text,
    location text,
    transaction_name text NOT NULL,
    success boolean NOT NULL,
    request_size integer,
    response_size integer,
    response_time integer,
    scenario_name text
);


--
-- Name: trends_filter_presets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trends_filter_presets (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    preset_type character varying(20) DEFAULT 'generic'::character varying NOT NULL,
    application_dashboard_id uuid,
    panel_id integer,
    panel_title character varying(255),
    evaluate_type character varying(20) DEFAULT 'avg'::character varying,
    source character varying(20) DEFAULT 'grafana'::character varying,
    dashboard_label character varying(255),
    series_config jsonb,
    created_for_test_run_id character varying(255),
    is_global boolean DEFAULT false NOT NULL,
    created_by character varying(255),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    organization_id uuid,
    team_id uuid,
    updated_by character varying(255)
);

ALTER TABLE ONLY public.trends_filter_presets FORCE ROW LEVEL SECURITY;


--
-- Name: url_patterns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.url_patterns (
    url_hash text NOT NULL,
    system_under_test text NOT NULL,
    test_environment text NOT NULL,
    normalized_url text NOT NULL,
    original_example text,
    first_seen timestamp with time zone NOT NULL,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255)
);

ALTER TABLE ONLY public.url_patterns FORCE ROW LEVEL SECURITY;


--
-- Name: versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.versions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    component character varying(255) NOT NULL,
    version character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: virtual_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.virtual_users (
    "time" timestamp with time zone NOT NULL,
    test_run_id text NOT NULL,
    system_under_test text,
    test_environment text,
    location text,
    node_name text NOT NULL,
    active_threads integer,
    started_threads integer,
    finished_threads integer,
    scenario_name text
);


--
-- Name: workload_apdex_thresholds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workload_apdex_thresholds (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    system_under_test_id text NOT NULL,
    test_environment text NOT NULL,
    workload text NOT NULL,
    apdex_threshold integer DEFAULT 500 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255),
    CONSTRAINT workload_apdex_thresholds_apdex_threshold_check CHECK (((apdex_threshold > 0) AND (apdex_threshold <= 60000)))
);


--
-- Name: workload_transaction_apdex_thresholds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workload_transaction_apdex_thresholds (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    system_under_test_id text NOT NULL,
    test_environment text NOT NULL,
    workload text NOT NULL,
    transaction_name text NOT NULL,
    apdex_threshold integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    organization_id uuid,
    team_id uuid,
    created_by character varying(255),
    updated_by character varying(255),
    CONSTRAINT workload_transaction_apdex_thresholds_apdex_threshold_check CHECK (((apdex_threshold > 0) AND (apdex_threshold <= 60000)))
);


--
-- Name: ds_change_points id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_change_points ALTER COLUMN id SET DEFAULT nextval('public.ds_change_points_id_seq'::regclass);


--
-- Name: ds_control_group_statistics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_control_group_statistics ALTER COLUMN id SET DEFAULT nextval('public.ds_control_group_statistics_id_seq'::regclass);


--
-- Name: ds_control_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_control_groups ALTER COLUMN id SET DEFAULT nextval('public.ds_control_groups_id_seq'::regclass);


--
-- Name: ds_panels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_panels ALTER COLUMN id SET DEFAULT nextval('public.ds_panels_id_seq'::regclass);


--
-- Name: migrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations ALTER COLUMN id SET DEFAULT nextval('public.migrations_id_seq'::regclass);


--
-- Name: awr_reports PK_028d58798e6c9432a32ce86755d; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awr_reports
    ADD CONSTRAINT "PK_028d58798e6c9432a32ce86755d" PRIMARY KEY (id);


--
-- Name: ds_change_points PK_06af2c6aafbad6659630ab8aafe; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_change_points
    ADD CONSTRAINT "PK_06af2c6aafbad6659630ab8aafe" PRIMARY KEY (id);


--
-- Name: expected_config_changes PK_0b991507efe6926adee967a22dd; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expected_config_changes
    ADD CONSTRAINT "PK_0b991507efe6926adee967a22dd" PRIMARY KEY (id);


--
-- Name: ds_metric_classification PK_12f5a3e063fa546e13463efb6c4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_metric_classification
    ADD CONSTRAINT "PK_12f5a3e063fa546e13463efb6c4" PRIMARY KEY (id);


--
-- Name: ds_compare_config PK_1cf4ec6238a44a9d482c9d3356f; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_compare_config
    ADD CONSTRAINT "PK_1cf4ec6238a44a9d482c9d3356f" PRIMARY KEY (id);


--
-- Name: profile_grafana_dashboards PK_2695ebd971f22836ef7a8f57711; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profile_grafana_dashboards
    ADD CONSTRAINT "PK_2695ebd971f22836ef7a8f57711" PRIMARY KEY (id);


--
-- Name: profile_benchmarks PK_2c827d461945bff03f072d8ddb4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profile_benchmarks
    ADD CONSTRAINT "PK_2c827d461945bff03f072d8ddb4" PRIMARY KEY (id);


--
-- Name: systems_under_test PK_2e4d6a5be9fb904ec1e98afd655; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.systems_under_test
    ADD CONSTRAINT "PK_2e4d6a5be9fb904ec1e98afd655" PRIMARY KEY (id);


--
-- Name: trends_filter_presets PK_2ea343ff8be02a772071e82a6eb; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trends_filter_presets
    ADD CONSTRAINT "PK_2ea343ff8be02a772071e82a6eb" PRIMARY KEY (id);


--
-- Name: generated_reports PK_3875618b27e8f2d438168399374; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generated_reports
    ADD CONSTRAINT "PK_3875618b27e8f2d438168399374" PRIMARY KEY (id);


--
-- Name: notification_channels PK_3bc0cb5b60e8659f5fc859b2af0; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_channels
    ADD CONSTRAINT "PK_3bc0cb5b60e8659f5fc859b2af0" PRIMARY KEY (id);


--
-- Name: tracing_services PK_3e3cab8c87e6181c440a0e1f7b1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracing_services
    ADD CONSTRAINT "PK_3e3cab8c87e6181c440a0e1f7b1" PRIMARY KEY (id);


--
-- Name: test_run_configs PK_440b17ebba9ec479c9d968ce1c2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_run_configs
    ADD CONSTRAINT "PK_440b17ebba9ec479c9d968ce1c2" PRIMARY KEY (id);


--
-- Name: deep_links PK_4c5c1e10a902f951e58475b50f9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deep_links
    ADD CONSTRAINT "PK_4c5c1e10a902f951e58475b50f9" PRIMARY KEY (id);


--
-- Name: ds_metric_statistics PK_59e025d1ee3248bd85656c29798; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_metric_statistics
    ADD CONSTRAINT "PK_59e025d1ee3248bd85656c29798" PRIMARY KEY (id);


--
-- Name: api_keys PK_5c8a79801b44bd27b79228e1dad; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT "PK_5c8a79801b44bd27b79228e1dad" PRIMARY KEY (id);


--
-- Name: pyroscope_instances PK_6396b14be0f34841c7cd76ec951; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pyroscope_instances
    ADD CONSTRAINT "PK_6396b14be0f34841c7cd76ec951" PRIMARY KEY (id);


--
-- Name: ds_adapt_tracked_results PK_66766c5a02ce9461e5b88d91db9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_adapt_tracked_results
    ADD CONSTRAINT "PK_66766c5a02ce9461e5b88d91db9" PRIMARY KEY (id);


--
-- Name: ds_control_group_statistics PK_6a7bb54688facb3823ccb4fb6fe; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_control_group_statistics
    ADD CONSTRAINT "PK_6a7bb54688facb3823ccb4fb6fe" PRIMARY KEY (id);


--
-- Name: organizations PK_6b031fcd0863e3f6b44230163f9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT "PK_6b031fcd0863e3f6b44230163f9" PRIMARY KEY (id);


--
-- Name: dynatrace_configs PK_6bb1e9c2afe5d72abc28b7667bb; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynatrace_configs
    ADD CONSTRAINT "PK_6bb1e9c2afe5d72abc28b7667bb" PRIMARY KEY (id);


--
-- Name: tracing_instances PK_7148a6a40ec67d7f73c01b0fb16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracing_instances
    ADD CONSTRAINT "PK_7148a6a40ec67d7f73c01b0fb16" PRIMARY KEY (id);


--
-- Name: grafana_dashboards PK_785560b584d8920471c29e627c3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grafana_dashboards
    ADD CONSTRAINT "PK_785560b584d8920471c29e627c3" PRIMARY KEY (id);


--
-- Name: benchmarks PK_7e1ca1c910680770da116e0b95c; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benchmarks
    ADD CONSTRAINT "PK_7e1ca1c910680770da116e0b95c" PRIMARY KEY (id);


--
-- Name: teams PK_7e5523774a38b08a6236d322403; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT "PK_7e5523774a38b08a6236d322403" PRIMARY KEY (id);


--
-- Name: grafana_instances PK_85d482cc93e6c7b9831a2f80217; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grafana_instances
    ADD CONSTRAINT "PK_85d482cc93e6c7b9831a2f80217" PRIMARY KEY (id);


--
-- Name: url_patterns PK_86771d227705fd40e7009153605; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.url_patterns
    ADD CONSTRAINT "PK_86771d227705fd40e7009153605" PRIMARY KEY (url_hash, system_under_test, test_environment);


--
-- Name: migrations PK_8c82d7f526340ab734260ea46be; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations
    ADD CONSTRAINT "PK_8c82d7f526340ab734260ea46be" PRIMARY KEY (id);


--
-- Name: ds_adapt_results PK_8d857bb499c732c569a9642ca98; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_adapt_results
    ADD CONSTRAINT "PK_8d857bb499c732c569a9642ca98" PRIMARY KEY (id);


--
-- Name: profiles PK_8e520eb4da7dc01d0e190447c8e; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT "PK_8e520eb4da7dc01d0e190447c8e" PRIMARY KEY (id);


--
-- Name: dynatrace_queries PK_9c3c4d972914dfe8bd57f796e55; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynatrace_queries
    ADD CONSTRAINT "PK_9c3c4d972914dfe8bd57f796e55" PRIMARY KEY (id);


--
-- Name: application_dashboards PK_a62f227b2fbbd8880bedde9eaf4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dashboards
    ADD CONSTRAINT "PK_a62f227b2fbbd8880bedde9eaf4" PRIMARY KEY (id);


--
-- Name: graph_presets PK_ade7f5aebcc026185a1f7e1e0f5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_presets
    ADD CONSTRAINT "PK_ade7f5aebcc026185a1f7e1e0f5" PRIMARY KEY (id);


--
-- Name: ds_metric_collection_status PK_b085e47f01230cf59565d2f1f3e; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_metric_collection_status
    ADD CONSTRAINT "PK_b085e47f01230cf59565d2f1f3e" PRIMARY KEY (id);


--
-- Name: generic_deep_links PK_b65d4356f0a6f4842cf331405cf; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generic_deep_links
    ADD CONSTRAINT "PK_b65d4356f0a6f4842cf331405cf" PRIMARY KEY (id);


--
-- Name: ds_control_groups PK_b91b14a88a53c54065628d9eca5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_control_groups
    ADD CONSTRAINT "PK_b91b14a88a53c54065628d9eca5" PRIMARY KEY (id);


--
-- Name: ds_panels PK_be96f0551113496d9ea187591ad; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_panels
    ADD CONSTRAINT "PK_be96f0551113496d9ea187591ad" PRIMARY KEY (id);


--
-- Name: ds_metrics PK_ced55abef6ba73d0d1e86a9660d; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_metrics
    ADD CONSTRAINT "PK_ced55abef6ba73d0d1e86a9660d" PRIMARY KEY (test_run_id, application_dashboard_id, dashboard_uid, panel_id, "time", metric_name);


--
-- Name: compare_filter_presets PK_d0afa9643aca930edb2979aa640; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.compare_filter_presets
    ADD CONSTRAINT "PK_d0afa9643aca930edb2979aa640" PRIMARY KEY (id);


--
-- Name: ds_adapt_conclusion PK_d7006261050e360c0ee33a5c4f5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_adapt_conclusion
    ADD CONSTRAINT "PK_d7006261050e360c0ee33a5c4f5" PRIMARY KEY (id);


--
-- Name: ds_tracked_differences PK_defc90daa43cb08380b0aacdef1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_tracked_differences
    ADD CONSTRAINT "PK_defc90daa43cb08380b0aacdef1" PRIMARY KEY (id);


--
-- Name: dynatrace_entity_mappings PK_e47f192baf0f8282e6c136f7844; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynatrace_entity_mappings
    ADD CONSTRAINT "PK_e47f192baf0f8282e6c136f7844" PRIMARY KEY (id);


--
-- Name: test_runs PK_ec4eca50c7ddfbd0dcf89b46dc6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_runs
    ADD CONSTRAINT "PK_ec4eca50c7ddfbd0dcf89b46dc6" PRIMARY KEY (id);


--
-- Name: events PK_events; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT "PK_events" PRIMARY KEY (id);


--
-- Name: awr_analysis PK_f41127106128c141a4bea2bed9e; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awr_analysis
    ADD CONSTRAINT "PK_f41127106128c141a4bea2bed9e" PRIMARY KEY (id);


--
-- Name: report_templates PK_f85e16e6beea41a2b3a3350b84e; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_templates
    ADD CONSTRAINT "PK_f85e16e6beea41a2b3a3350b84e" PRIMARY KEY (id);


--
-- Name: generated_reports UQ_022bdc75d66ca79a13432e027c9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generated_reports
    ADD CONSTRAINT "UQ_022bdc75d66ca79a13432e027c9" UNIQUE (share_id);


--
-- Name: expected_config_changes UQ_18c708f793ea6de2785b0515192; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expected_config_changes
    ADD CONSTRAINT "UQ_18c708f793ea6de2785b0515192" UNIQUE (system_under_test_id, test_environment, workload, config_key);


--
-- Name: profiles UQ_4e9da7cade0e9edd393329bb326; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT "UQ_4e9da7cade0e9edd393329bb326" UNIQUE (name);


--
-- Name: test_runs UQ_8bdcd42f6c06f199f59e2c475f1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_runs
    ADD CONSTRAINT "UQ_8bdcd42f6c06f199f59e2c475f1" UNIQUE (test_run_id);


--
-- Name: tracing_instances UQ_8e3f86a32ab0862024fe68fa7d1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracing_instances
    ADD CONSTRAINT "UQ_8e3f86a32ab0862024fe68fa7d1" UNIQUE (label);


--
-- Name: api_keys UQ_9ccce5863aec84d045d778179de; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT "UQ_9ccce5863aec84d045d778179de" UNIQUE (api_key);


--
-- Name: api_keys api_keys_api_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_api_key_key UNIQUE (api_key);


--
-- Name: api_keys api_keys_description_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_description_key UNIQUE (description);


--
-- Name: system_under_test_test_environments application_test_environments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_under_test_test_environments
    ADD CONSTRAINT application_test_environments_pkey PRIMARY KEY (id);


--
-- Name: system_under_test_workloads application_test_types_application_test_environment_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_under_test_workloads
    ADD CONSTRAINT application_test_types_application_test_environment_id_name_key UNIQUE (system_under_test_test_environment_id, name);


--
-- Name: system_under_test_workloads application_test_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_under_test_workloads
    ADD CONSTRAINT application_test_types_pkey PRIMARY KEY (id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: check_results check_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_results
    ADD CONSTRAINT check_results_pkey PRIMARY KEY (id);


--
-- Name: configuration configuration_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configuration
    ADD CONSTRAINT configuration_pkey PRIMARY KEY (id);


--
-- Name: configuration configuration_type_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configuration
    ADD CONSTRAINT configuration_type_key_key UNIQUE (type, key);


--
-- Name: data_sources data_sources_organization_id_source_type_instance_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_sources
    ADD CONSTRAINT data_sources_organization_id_source_type_instance_name_key UNIQUE (organization_id, source_type, instance_name);


--
-- Name: data_sources data_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_sources
    ADD CONSTRAINT data_sources_pkey PRIMARY KEY (id);


--
-- Name: ds_adapt_conclusion ds_adapt_conclusion_test_run_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_adapt_conclusion
    ADD CONSTRAINT ds_adapt_conclusion_test_run_id_key UNIQUE (test_run_id);


--
-- Name: ds_adapt_tracked_results ds_adapt_tracked_results_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_adapt_tracked_results
    ADD CONSTRAINT ds_adapt_tracked_results_unique UNIQUE (test_run_id, application_dashboard_id, panel_id, metric_name, tracked_test_run_id);


--
-- Name: ds_control_groups ds_control_groups_control_group_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_control_groups
    ADD CONSTRAINT ds_control_groups_control_group_id_key UNIQUE (control_group_id);


--
-- Name: ds_metric_statistics ds_metric_statistics_unique_metric; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_metric_statistics
    ADD CONSTRAINT ds_metric_statistics_unique_metric UNIQUE (test_run_id, application_dashboard_id, panel_id, metric_name);


--
-- Name: ds_queries ds_queries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_queries
    ADD CONSTRAINT ds_queries_pkey PRIMARY KEY (id);


--
-- Name: ds_queries ds_queries_source_type_source_instance_query_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_queries
    ADD CONSTRAINT ds_queries_source_type_source_instance_query_hash_key UNIQUE (source_type, source_instance, query_hash);


--
-- Name: ds_query_executions ds_query_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_query_executions
    ADD CONSTRAINT ds_query_executions_pkey PRIMARY KEY (id);


--
-- Name: dynatrace_configs dynatrace_configs_host_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynatrace_configs
    ADD CONSTRAINT dynatrace_configs_host_key UNIQUE (host);


--
-- Name: expected_config_changes expected_config_changes_system_under_test_id_test_environme_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expected_config_changes
    ADD CONSTRAINT expected_config_changes_system_under_test_id_test_environme_key UNIQUE (system_under_test_id, test_environment, workload, config_key);


--
-- Name: grafana_instances grafana_instances_label_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grafana_instances
    ADD CONSTRAINT grafana_instances_label_key UNIQUE (label);


--
-- Name: licenses licenses_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.licenses
    ADD CONSTRAINT licenses_key_key UNIQUE (key);


--
-- Name: licenses licenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.licenses
    ADD CONSTRAINT licenses_pkey PRIMARY KEY (id);


--
-- Name: organization_members organization_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_members
    ADD CONSTRAINT organization_members_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_name_key UNIQUE (name);


--
-- Name: pending_ds_compare_config_changes pending_ds_compare_config_changes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pending_ds_compare_config_changes
    ADD CONSTRAINT pending_ds_compare_config_changes_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_name_key UNIQUE (name);


--
-- Name: system_under_test_test_environments system_under_test_test_environments_system_under_test_id_name_k; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_under_test_test_environments
    ADD CONSTRAINT system_under_test_test_environments_system_under_test_id_name_k UNIQUE (system_under_test_id, name);


--
-- Name: team_members team_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_pkey PRIMARY KEY (id);


--
-- Name: test_run_alerts test_run_alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_run_alerts
    ADD CONSTRAINT test_run_alerts_pkey PRIMARY KEY (id);


--
-- Name: test_run_configs_test_run_id_key_tags_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX test_run_configs_test_run_id_key_tags_key
    ON public.test_run_configs USING btree (test_run_id, key, public.tags_hash(tags));


--
-- Name: test_run_events test_run_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_run_events
    ADD CONSTRAINT test_run_events_pkey PRIMARY KEY (id);


--
-- Name: test_runs test_runs_application_id_test_environment_test_type_test_ru_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_runs
    ADD CONSTRAINT test_runs_application_id_test_environment_test_type_test_ru_key UNIQUE (system_under_test_id, test_environment, workload, test_run_id);


--
-- Name: tracing_instances tracing_instances_label_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracing_instances
    ADD CONSTRAINT tracing_instances_label_key UNIQUE (label);


--
-- Name: ds_adapt_results uk_ds_adapt_results_business_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_adapt_results
    ADD CONSTRAINT uk_ds_adapt_results_business_key UNIQUE (test_run_id, control_group_id, application_dashboard_id, panel_id, metric_name);


--
-- Name: profile_grafana_dashboards unique_profile_dashboard_grafana; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profile_grafana_dashboards
    ADD CONSTRAINT unique_profile_dashboard_grafana UNIQUE (profile, dashboard_uid, grafana_label);


--
-- Name: workload_apdex_thresholds unique_workload_threshold; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workload_apdex_thresholds
    ADD CONSTRAINT unique_workload_threshold UNIQUE (system_under_test_id, test_environment, workload);


--
-- Name: workload_transaction_apdex_thresholds unique_workload_transaction_threshold; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workload_transaction_apdex_thresholds
    ADD CONSTRAINT unique_workload_transaction_threshold UNIQUE (system_under_test_id, test_environment, workload, transaction_name);


--
-- Name: application_dashboards uq_application_dashboards_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dashboards
    ADD CONSTRAINT uq_application_dashboards_unique UNIQUE (system_under_test_id, test_environment, grafana_instance_id, dashboard_uid, dashboard_label);


--
-- Name: benchmarks uq_benchmarks_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benchmarks
    ADD CONSTRAINT uq_benchmarks_unique UNIQUE (system_under_test_id, test_environment, workload, application_dashboard_id, generic_check_id);


--
-- Name: notification_channels uq_notification_channels_system_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_channels
    ADD CONSTRAINT uq_notification_channels_system_name UNIQUE (system_under_test_id, name);


--
-- Name: organization_members uq_organization_members_user_org; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_members
    ADD CONSTRAINT uq_organization_members_user_org UNIQUE (organization_id, user_id);


--
-- Name: report_templates uq_report_templates_name_scope; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_templates
    ADD CONSTRAINT uq_report_templates_name_scope UNIQUE (name, system_id, test_environment, workload);


--
-- Name: team_members uq_team_members_user_team; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT uq_team_members_user_team UNIQUE (team_id, user_id);


--
-- Name: tracing_services uq_tracing_services_config; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracing_services
    ADD CONSTRAINT uq_tracing_services_config UNIQUE (system_under_test_id, test_environment, workload, tracing_instance_id);


--
-- Name: versions versions_component_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT versions_component_version_key UNIQUE (component, version);


--
-- Name: versions versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT versions_pkey PRIMARY KEY (id);


--
-- Name: workload_apdex_thresholds workload_apdex_thresholds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workload_apdex_thresholds
    ADD CONSTRAINT workload_apdex_thresholds_pkey PRIMARY KEY (id);


--
-- Name: workload_transaction_apdex_thresholds workload_transaction_apdex_thresholds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workload_transaction_apdex_thresholds
    ADD CONSTRAINT workload_transaction_apdex_thresholds_pkey PRIMARY KEY (id);


--
-- Name: IDX_008825f84d7351df73c0546d6d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_008825f84d7351df73c0546d6d" ON public.compare_filter_presets USING btree (is_global);


--
-- Name: IDX_261d1c1d7d43b94a9f0a8601db; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_261d1c1d7d43b94a9f0a8601db" ON public.graph_presets USING btree (test_run_id) WHERE (test_run_id IS NOT NULL);


--
-- Name: IDX_32d4b19a96d6ff07e7e7102040; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_32d4b19a96d6ff07e7e7102040" ON public.application_dashboards USING btree (dashboard_uid);


--
-- Name: IDX_4546dbef3a700472fa8fe06df4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_4546dbef3a700472fa8fe06df4" ON public.compare_filter_presets USING btree (preset_type);


--
-- Name: IDX_534c79bce8e9bb98958f3f1b5e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_534c79bce8e9bb98958f3f1b5e" ON public.trends_filter_presets USING btree (created_by);


--
-- Name: IDX_5950c33a12a87b85beaff4a430; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_5950c33a12a87b85beaff4a430" ON public.notification_channels USING btree (system_under_test_id);


--
-- Name: IDX_60be5a799bbd19f5c046aaaecf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_60be5a799bbd19f5c046aaaecf" ON public.grafana_dashboards USING btree (name);


--
-- Name: IDX_6d4d25020a25d7ef8db9e8040b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_6d4d25020a25d7ef8db9e8040b" ON public.graph_presets USING btree (name);


--
-- Name: IDX_7b8c895fd44f497e8608b8c5cb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_7b8c895fd44f497e8608b8c5cb" ON public.trends_filter_presets USING btree (name);


--
-- Name: IDX_9225364cbd7174db8a78ac4c86; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_9225364cbd7174db8a78ac4c86" ON public.compare_filter_presets USING btree (application_dashboard_id) WHERE (application_dashboard_id IS NOT NULL);


--
-- Name: IDX_94aedf2600de58083afbe707cd; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_94aedf2600de58083afbe707cd" ON public.tracing_services USING btree (system_under_test_id, test_environment, workload, tracing_instance_id);


--
-- Name: IDX_96eeab5508e1325b1b4407bfa4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_96eeab5508e1325b1b4407bfa4" ON public.trends_filter_presets USING btree (preset_type);


--
-- Name: IDX_98037b86341442463acdcf81d2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_98037b86341442463acdcf81d2" ON public.application_dashboards USING btree (test_environment);


--
-- Name: IDX_982c75e205f73579654b88b376; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_982c75e205f73579654b88b376" ON public.trends_filter_presets USING btree (is_global);


--
-- Name: IDX_9900d24670c8b447abc3b88a06; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_9900d24670c8b447abc3b88a06" ON public.graph_presets USING btree (is_global);


--
-- Name: IDX_a7b2d4a5425c8e087ab8014e3f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_a7b2d4a5425c8e087ab8014e3f" ON public.application_dashboards USING btree (system_under_test_id);


--
-- Name: IDX_b0cc8447598414fda692d5225b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_b0cc8447598414fda692d5225b" ON public.application_dashboards USING btree (system_under_test_id, test_environment);


--
-- Name: IDX_b59372b5ad31411f620a9f1b78; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_b59372b5ad31411f620a9f1b78" ON public.compare_filter_presets USING btree (created_for_test_run_id) WHERE (created_for_test_run_id IS NOT NULL);


--
-- Name: IDX_bbd36f33b0dfc25aee130a5c28; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_bbd36f33b0dfc25aee130a5c28" ON public.application_dashboards USING btree (dashboard_label);


--
-- Name: IDX_bc8e37da09491e8f5cc9f0a93d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_bc8e37da09491e8f5cc9f0a93d" ON public.graph_presets USING btree (user_id);


--
-- Name: IDX_c0143e62b384490aeb5e1e0a86; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_c0143e62b384490aeb5e1e0a86" ON public.trends_filter_presets USING btree (created_for_test_run_id) WHERE (created_for_test_run_id IS NOT NULL);


--
-- Name: IDX_c51ab2014ab264427902fcefec; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_c51ab2014ab264427902fcefec" ON public.ds_metric_collection_status USING btree (test_run_id, source_type, source_id);


--
-- Name: IDX_c7195e7ce3f0b1c0ac2b9b256a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_c7195e7ce3f0b1c0ac2b9b256a" ON public.compare_filter_presets USING btree (name);


--
-- Name: IDX_d7c24e2aad8410112f1fd6785e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_d7c24e2aad8410112f1fd6785e" ON public.grafana_dashboards USING btree (grafana_instance_id);


--
-- Name: IDX_e28e6efada86e9da60cf480294; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_e28e6efada86e9da60cf480294" ON public.graph_presets USING btree (user_id, test_run_id);


--
-- Name: IDX_e4e4c98b2c9634e601b2ab655d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_e4e4c98b2c9634e601b2ab655d" ON public.compare_filter_presets USING btree (created_by);


--
-- Name: IDX_e4ef59a577e7195fcbc86f4b32; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_e4ef59a577e7195fcbc86f4b32" ON public.grafana_dashboards USING btree (uid);


--
-- Name: IDX_e7b0832c5e9bb206704c511f29; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_e7b0832c5e9bb206704c511f29" ON public.application_dashboards USING btree (grafana_instance_id);


--
-- Name: IDX_f705ea42d61dd455d5a9cc8f1a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_f705ea42d61dd455d5a9cc8f1a" ON public.notification_channels USING btree (enabled);


--
-- Name: IDX_f7ef2f635a3a3e941e19404e76; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_f7ef2f635a3a3e941e19404e76" ON public.trends_filter_presets USING btree (application_dashboard_id) WHERE (application_dashboard_id IS NOT NULL);


--
-- Name: IDX_fbae9e222dde1d3850c895dc5a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_fbae9e222dde1d3850c895dc5a" ON public.application_dashboards USING btree (grafana_dashboard_id);


--
-- Name: ds_compare_config_metric_level_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ds_compare_config_metric_level_unique ON public.ds_compare_config USING btree (application_dashboard_id, panel_id, metric_name) WHERE (metric_name IS NOT NULL);


--
-- Name: ds_compare_config_panel_level_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ds_compare_config_panel_level_unique ON public.ds_compare_config USING btree (application_dashboard_id, panel_id) WHERE (metric_name IS NULL);


--
-- Name: ds_metrics_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ds_metrics_time_idx ON public.ds_metrics USING btree ("time" DESC);


--
-- Name: idx_api_keys_api_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_keys_api_key ON public.api_keys USING btree (api_key);


--
-- Name: idx_api_keys_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_keys_created_by ON public.api_keys USING btree (created_by);


--
-- Name: idx_api_keys_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_keys_organization_id ON public.api_keys USING btree (organization_id);


--
-- Name: idx_api_keys_roles; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_keys_roles ON public.api_keys USING btree (roles);


--
-- Name: idx_api_keys_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_keys_team_id ON public.api_keys USING btree (team_id);


--
-- Name: idx_api_keys_valid_until; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_keys_valid_until ON public.api_keys USING btree (valid_until);


--
-- Name: idx_application_dashboards_dashboard_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_application_dashboards_dashboard_id ON public.application_dashboards USING btree (grafana_dashboard_id);


--
-- Name: idx_application_dashboards_environment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_application_dashboards_environment ON public.application_dashboards USING btree (test_environment);


--
-- Name: idx_application_dashboards_grafana_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_application_dashboards_grafana_id ON public.application_dashboards USING btree (grafana_instance_id);


--
-- Name: idx_application_dashboards_label; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_application_dashboards_label ON public.application_dashboards USING btree (dashboard_label);


--
-- Name: idx_application_dashboards_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_application_dashboards_organization_id ON public.application_dashboards USING btree (organization_id);


--
-- Name: idx_application_dashboards_system_env; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_application_dashboards_system_env ON public.application_dashboards USING btree (system_under_test_id, test_environment);


--
-- Name: idx_application_dashboards_system_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_application_dashboards_system_id ON public.application_dashboards USING btree (system_under_test_id);


--
-- Name: idx_application_dashboards_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_application_dashboards_team_id ON public.application_dashboards USING btree (team_id);


--
-- Name: idx_application_dashboards_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_application_dashboards_uid ON public.application_dashboards USING btree (dashboard_uid);


--
-- Name: idx_application_dashboards_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_application_dashboards_unique ON public.application_dashboards USING btree (system_under_test_id, test_environment, grafana_instance_id, dashboard_uid, dashboard_label);


--
-- Name: idx_applications_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_applications_name ON public.systems_under_test USING btree (name);


--
-- Name: idx_applications_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_applications_team_id ON public.systems_under_test USING btree (team_id);


--
-- Name: idx_audit_logs_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_action ON public.audit_logs USING btree (action);


--
-- Name: idx_audit_logs_org_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_org_timestamp ON public.audit_logs USING btree (organization_id, "timestamp" DESC);


--
-- Name: idx_audit_logs_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_organization_id ON public.audit_logs USING btree (organization_id);


--
-- Name: idx_audit_logs_resource_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_resource_id ON public.audit_logs USING btree (resource_id);


--
-- Name: idx_audit_logs_resource_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_resource_type ON public.audit_logs USING btree (resource_type);


--
-- Name: idx_audit_logs_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_timestamp ON public.audit_logs USING btree ("timestamp" DESC);


--
-- Name: idx_audit_logs_user_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_user_action ON public.audit_logs USING btree (user_id, action);


--
-- Name: idx_audit_logs_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_user_id ON public.audit_logs USING btree (user_id);


--
-- Name: idx_awr_analysis_analysis_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_analysis_analysis_type ON public.awr_analysis USING btree (analysis_type);


--
-- Name: idx_awr_analysis_analyzed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_analysis_analyzed_at ON public.awr_analysis USING btree (analyzed_at);


--
-- Name: idx_awr_analysis_awr_report_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_analysis_awr_report_id ON public.awr_analysis USING btree (awr_report_id);


--
-- Name: idx_awr_analysis_baseline_report_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_analysis_baseline_report_id ON public.awr_analysis USING btree (baseline_report_id);


--
-- Name: idx_awr_analysis_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_analysis_created_by ON public.awr_analysis USING btree (created_by);


--
-- Name: idx_awr_analysis_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_analysis_organization_id ON public.awr_analysis USING btree (organization_id);


--
-- Name: idx_awr_analysis_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_analysis_team_id ON public.awr_analysis USING btree (team_id);


--
-- Name: idx_awr_reports_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_reports_created_by ON public.awr_reports USING btree (created_by);


--
-- Name: idx_awr_reports_db_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_reports_db_name ON public.awr_reports USING btree (db_name);


--
-- Name: idx_awr_reports_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_reports_organization_id ON public.awr_reports USING btree (organization_id);


--
-- Name: idx_awr_reports_parse_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_reports_parse_status ON public.awr_reports USING btree (parse_status);


--
-- Name: idx_awr_reports_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_reports_team_id ON public.awr_reports USING btree (team_id);


--
-- Name: idx_awr_reports_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_reports_test_run_id ON public.awr_reports USING btree (test_run_id);


--
-- Name: idx_awr_reports_uploaded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awr_reports_uploaded_at ON public.awr_reports USING btree (uploaded_at);


--
-- Name: idx_benchmarks_apdex_transaction; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_apdex_transaction ON public.benchmarks USING btree (system_under_test_id, test_environment, workload, transaction_name) WHERE ((benchmark_type)::text = 'apdex'::text);


--
-- Name: idx_benchmarks_config_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_config_title ON public.benchmarks USING btree (config_title);


--
-- Name: idx_benchmarks_configuration_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_configuration_gin ON public.benchmarks USING gin (configuration);


--
-- Name: idx_benchmarks_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_created_by ON public.benchmarks USING btree (created_by);


--
-- Name: idx_benchmarks_dashboard_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_dashboard_uid ON public.benchmarks USING btree (dashboard_uid) WHERE ((source)::text = 'grafana'::text);


--
-- Name: idx_benchmarks_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_enabled ON public.benchmarks USING btree (enabled) WHERE (enabled = true);


--
-- Name: idx_benchmarks_evaluate_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_evaluate_type ON public.benchmarks USING btree (evaluate_type);


--
-- Name: idx_benchmarks_generic_check_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_generic_check_id ON public.benchmarks USING btree (generic_check_id) WHERE (generic_check_id IS NOT NULL);


--
-- Name: idx_benchmarks_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_organization_id ON public.benchmarks USING btree (organization_id);


--
-- Name: idx_benchmarks_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_source ON public.benchmarks USING btree (source);


--
-- Name: idx_benchmarks_sut_source_env_workload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_sut_source_env_workload ON public.benchmarks USING btree (system_under_test_id, source, test_environment, workload);


--
-- Name: idx_benchmarks_system_under_test_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_system_under_test_id ON public.benchmarks USING btree (system_under_test_id);


--
-- Name: idx_benchmarks_tags_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_tags_gin ON public.benchmarks USING gin (tags);


--
-- Name: idx_benchmarks_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_team_id ON public.benchmarks USING btree (team_id);


--
-- Name: idx_benchmarks_test_env; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_test_env ON public.benchmarks USING btree (test_environment);


--
-- Name: idx_benchmarks_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_type ON public.benchmarks USING btree (benchmark_type);


--
-- Name: idx_benchmarks_unique_grafana; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_benchmarks_unique_grafana ON public.benchmarks USING btree (system_under_test_id, source, test_environment, workload, dashboard_uid, config_id, dashboard_label) WHERE ((enabled = true) AND ((source)::text = 'grafana'::text));


--
-- Name: idx_benchmarks_unique_non_grafana; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_benchmarks_unique_non_grafana ON public.benchmarks USING btree (system_under_test_id, source, test_environment, workload, config_title) WHERE ((enabled = true) AND ((source)::text <> 'grafana'::text));


--
-- Name: idx_benchmarks_valid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_valid ON public.benchmarks USING btree (valid) WHERE (valid = true);


--
-- Name: idx_benchmarks_workload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benchmarks_workload ON public.benchmarks USING btree (workload);


--
-- Name: idx_check_results_benchmark_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_benchmark_gin ON public.check_results USING gin (benchmark);


--
-- Name: idx_check_results_benchmark_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_benchmark_id ON public.check_results USING btree (benchmark_id);


--
-- Name: idx_check_results_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_created_by ON public.check_results USING btree (created_by);


--
-- Name: idx_check_results_dashboard_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_dashboard_uid ON public.check_results USING btree (dashboard_uid);


--
-- Name: idx_check_results_dynatrace_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_dynatrace_entity ON public.check_results USING btree (dynatrace_entity_id);


--
-- Name: idx_check_results_dynatrace_filters_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_dynatrace_filters_gin ON public.check_results USING gin (dynatrace_dimension_filters);


--
-- Name: idx_check_results_evaluate_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_evaluate_type ON public.check_results USING btree (evaluate_type);


--
-- Name: idx_check_results_meets_requirement; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_meets_requirement ON public.check_results USING btree (meets_requirement);


--
-- Name: idx_check_results_metadata_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_metadata_gin ON public.check_results USING gin (metadata);


--
-- Name: idx_check_results_metric_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_metric_name ON public.check_results USING btree (metric_name);


--
-- Name: idx_check_results_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_organization_id ON public.check_results USING btree (organization_id);


--
-- Name: idx_check_results_requirement_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_requirement_gin ON public.check_results USING gin (requirement);


--
-- Name: idx_check_results_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_source ON public.check_results USING btree (source);


--
-- Name: idx_check_results_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_status ON public.check_results USING btree (status);


--
-- Name: idx_check_results_sut_source_env_workload_testrun; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_sut_source_env_workload_testrun ON public.check_results USING btree (system_under_test_id, source, test_environment, workload, test_run_id);


--
-- Name: idx_check_results_system_under_test_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_system_under_test_id ON public.check_results USING btree (system_under_test_id);


--
-- Name: idx_check_results_targets_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_targets_gin ON public.check_results USING gin (targets);


--
-- Name: idx_check_results_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_team_id ON public.check_results USING btree (team_id);


--
-- Name: idx_check_results_test_env; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_test_env ON public.check_results USING btree (test_environment);


--
-- Name: idx_check_results_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_test_run_id ON public.check_results USING btree (test_run_id);


--
-- Name: idx_check_results_workload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_results_workload ON public.check_results USING btree (workload);


--
-- Name: idx_collection_status_incomplete; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_collection_status_incomplete ON public.ds_metric_collection_status USING btree (test_run_id) WHERE (is_complete = false);


--
-- Name: idx_collection_status_test_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_collection_status_test_run ON public.ds_metric_collection_status USING btree (test_run_id);


--
-- Name: idx_compare_config_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compare_config_lookup ON public.ds_compare_config USING btree (system_under_test_id, test_environment, workload, application_dashboard_id, panel_id, metric_name);


--
-- Name: idx_compare_filter_presets_app_dashboard; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compare_filter_presets_app_dashboard ON public.compare_filter_presets USING btree (application_dashboard_id) WHERE (application_dashboard_id IS NOT NULL);


--
-- Name: idx_compare_filter_presets_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compare_filter_presets_created_by ON public.compare_filter_presets USING btree (created_by);


--
-- Name: idx_compare_filter_presets_created_for_test_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compare_filter_presets_created_for_test_run ON public.compare_filter_presets USING btree (created_for_test_run_id) WHERE (created_for_test_run_id IS NOT NULL);


--
-- Name: idx_compare_filter_presets_global; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compare_filter_presets_global ON public.compare_filter_presets USING btree (is_global);


--
-- Name: idx_compare_filter_presets_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compare_filter_presets_name ON public.compare_filter_presets USING btree (name);


--
-- Name: idx_compare_filter_presets_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compare_filter_presets_organization_id ON public.compare_filter_presets USING btree (organization_id);


--
-- Name: idx_compare_filter_presets_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compare_filter_presets_team_id ON public.compare_filter_presets USING btree (team_id);


--
-- Name: idx_compare_filter_presets_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compare_filter_presets_type ON public.compare_filter_presets USING btree (preset_type);


--
-- Name: idx_deep_links_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deep_links_created_by ON public.deep_links USING btree (created_by);


--
-- Name: idx_deep_links_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deep_links_lookup ON public.deep_links USING btree (system_under_test_id, test_environment, workload);


--
-- Name: idx_deep_links_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deep_links_organization_id ON public.deep_links USING btree (organization_id);


--
-- Name: idx_deep_links_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deep_links_team_id ON public.deep_links USING btree (team_id);


--
-- Name: idx_deep_links_template; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deep_links_template ON public.deep_links USING btree (template_deep_link_id) WHERE (template_deep_link_id IS NOT NULL);


--
-- Name: idx_ds_adapt_conclusion_conclusion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_conclusion ON public.ds_adapt_conclusion USING btree (conclusion);


--
-- Name: idx_ds_adapt_conclusion_control_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_control_group_id ON public.ds_adapt_conclusion USING btree (control_group_id) WHERE (control_group_id IS NOT NULL);


--
-- Name: idx_ds_adapt_conclusion_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_created_by ON public.ds_adapt_conclusion USING btree (created_by);


--
-- Name: idx_ds_adapt_conclusion_details_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_details_gin ON public.ds_adapt_conclusion USING gin (details);


--
-- Name: idx_ds_adapt_conclusion_details_message; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_details_message ON public.ds_adapt_conclusion USING btree (((details ->> 'message'::text)));


--
-- Name: idx_ds_adapt_conclusion_differences_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_differences_gin ON public.ds_adapt_conclusion USING gin (differences);


--
-- Name: idx_ds_adapt_conclusion_improvements_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_improvements_gin ON public.ds_adapt_conclusion USING gin (improvements);


--
-- Name: idx_ds_adapt_conclusion_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_organization_id ON public.ds_adapt_conclusion USING btree (organization_id);


--
-- Name: idx_ds_adapt_conclusion_regressions_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_regressions_gin ON public.ds_adapt_conclusion USING gin (regressions);


--
-- Name: idx_ds_adapt_conclusion_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_team_id ON public.ds_adapt_conclusion USING btree (team_id);


--
-- Name: idx_ds_adapt_conclusion_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_test_run_id ON public.ds_adapt_conclusion USING btree (test_run_id);


--
-- Name: idx_ds_adapt_conclusion_tracked_regressions_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_tracked_regressions_gin ON public.ds_adapt_conclusion USING gin (tracked_regressions);


--
-- Name: idx_ds_adapt_conclusion_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_conclusion_updated_at ON public.ds_adapt_conclusion USING btree (updated_at DESC);


--
-- Name: idx_ds_adapt_results_compare_config_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_compare_config_gin ON public.ds_adapt_results USING gin (compare_config);


--
-- Name: idx_ds_adapt_results_conclusion_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_conclusion_gin ON public.ds_adapt_results USING gin (conclusion);


--
-- Name: idx_ds_adapt_results_conclusion_label; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_conclusion_label ON public.ds_adapt_results USING btree (((conclusion ->> 'label'::text)));


--
-- Name: idx_ds_adapt_results_control_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_control_group_id ON public.ds_adapt_results USING btree (control_group_id);


--
-- Name: idx_ds_adapt_results_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_created_by ON public.ds_adapt_results USING btree (created_by);


--
-- Name: idx_ds_adapt_results_dashboard; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_dashboard ON public.ds_adapt_results USING btree (application_dashboard_id, panel_id);


--
-- Name: idx_ds_adapt_results_metric; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_metric ON public.ds_adapt_results USING btree (metric_name);


--
-- Name: idx_ds_adapt_results_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_organization_id ON public.ds_adapt_results USING btree (organization_id);


--
-- Name: idx_ds_adapt_results_stale; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_stale ON public.ds_adapt_results USING btree (test_run_id, is_stale) WHERE (is_stale = true);


--
-- Name: idx_ds_adapt_results_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_team_id ON public.ds_adapt_results USING btree (team_id);


--
-- Name: idx_ds_adapt_results_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_test_run_id ON public.ds_adapt_results USING btree (test_run_id);


--
-- Name: idx_ds_adapt_results_test_run_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_test_run_start ON public.ds_adapt_results USING btree (test_run_start);


--
-- Name: idx_ds_adapt_results_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_results_updated_at ON public.ds_adapt_results USING btree (updated_at);


--
-- Name: idx_ds_adapt_tracked_results_checks_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_checks_gin ON public.ds_adapt_tracked_results USING gin (checks);


--
-- Name: idx_ds_adapt_tracked_results_conclusion_analysis; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_conclusion_analysis ON public.ds_adapt_tracked_results USING gin (((conclusion -> 'label'::text))) WHERE (conclusion IS NOT NULL);


--
-- Name: idx_ds_adapt_tracked_results_control_group; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_control_group ON public.ds_adapt_tracked_results USING btree (control_group_id, test_run_start DESC);


--
-- Name: idx_ds_adapt_tracked_results_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_created_by ON public.ds_adapt_tracked_results USING btree (created_by);


--
-- Name: idx_ds_adapt_tracked_results_dashboard; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_dashboard ON public.ds_adapt_tracked_results USING btree (application_dashboard_id, test_run_start DESC);


--
-- Name: idx_ds_adapt_tracked_results_mean_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_mean_gin ON public.ds_adapt_tracked_results USING gin (mean);


--
-- Name: idx_ds_adapt_tracked_results_median_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_median_gin ON public.ds_adapt_tracked_results USING gin (median);


--
-- Name: idx_ds_adapt_tracked_results_metric_tracking; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_metric_tracking ON public.ds_adapt_tracked_results USING btree (application_dashboard_id, panel_id, metric_name, control_group_id, test_run_start DESC);


--
-- Name: idx_ds_adapt_tracked_results_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_organization_id ON public.ds_adapt_tracked_results USING btree (organization_id);


--
-- Name: idx_ds_adapt_tracked_results_panel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_panel ON public.ds_adapt_tracked_results USING btree (application_dashboard_id, panel_id, test_run_start DESC);


--
-- Name: idx_ds_adapt_tracked_results_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_team_id ON public.ds_adapt_tracked_results USING btree (team_id);


--
-- Name: idx_ds_adapt_tracked_results_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_test_run_id ON public.ds_adapt_tracked_results USING btree (test_run_id);


--
-- Name: idx_ds_adapt_tracked_results_time_series; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_time_series ON public.ds_adapt_tracked_results USING btree (application_dashboard_id, panel_id, metric_name, test_run_start DESC);


--
-- Name: idx_ds_adapt_tracked_results_tracked_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_adapt_tracked_results_tracked_test_run_id ON public.ds_adapt_tracked_results USING btree (tracked_test_run_id);


--
-- Name: idx_ds_change_points_application_dashboard_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_change_points_application_dashboard_id ON public.ds_change_points USING btree (application_dashboard_id);


--
-- Name: idx_ds_change_points_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_change_points_composite ON public.ds_change_points USING btree (system_under_test_id, workload, test_environment);


--
-- Name: idx_ds_change_points_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_change_points_created_by ON public.ds_change_points USING btree (created_by);


--
-- Name: idx_ds_change_points_metric_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_change_points_metric_name ON public.ds_change_points USING btree (metric_name);


--
-- Name: idx_ds_change_points_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_change_points_organization_id ON public.ds_change_points USING btree (organization_id);


--
-- Name: idx_ds_change_points_panel_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_change_points_panel_composite ON public.ds_change_points USING btree (application_dashboard_id, panel_id, metric_name);


--
-- Name: idx_ds_change_points_panel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_change_points_panel_id ON public.ds_change_points USING btree (panel_id);


--
-- Name: idx_ds_change_points_system_under_test_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_change_points_system_under_test_id ON public.ds_change_points USING btree (system_under_test_id);


--
-- Name: idx_ds_change_points_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_change_points_team_id ON public.ds_change_points USING btree (team_id);


--
-- Name: idx_ds_change_points_test_environment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_change_points_test_environment ON public.ds_change_points USING btree (test_environment);


--
-- Name: idx_ds_change_points_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_change_points_test_run_id ON public.ds_change_points USING btree (test_run_id);


--
-- Name: idx_ds_change_points_workload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_change_points_workload ON public.ds_change_points USING btree (workload);


--
-- Name: idx_ds_compare_config_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_compare_config_created_by ON public.ds_compare_config USING btree (created_by);


--
-- Name: idx_ds_compare_config_dashboard_fallback; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_compare_config_dashboard_fallback ON public.ds_compare_config USING btree (system_under_test_id, test_environment, workload, application_dashboard_id) WHERE ((metric_name IS NULL) AND (panel_id IS NULL));


--
-- Name: idx_ds_compare_config_environment_fallback; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_compare_config_environment_fallback ON public.ds_compare_config USING btree (system_under_test_id, test_environment, workload) WHERE ((metric_name IS NULL) AND (panel_id IS NULL) AND (application_dashboard_id IS NULL));


--
-- Name: idx_ds_compare_config_global_fallback; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_compare_config_global_fallback ON public.ds_compare_config USING btree (system_under_test_id, workload) WHERE ((metric_name IS NULL) AND (panel_id IS NULL) AND (application_dashboard_id IS NULL) AND (test_environment IS NULL));


--
-- Name: idx_ds_compare_config_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_compare_config_hash ON public.ds_compare_config USING btree (system_under_test_id, test_environment, workload, config_hash);


--
-- Name: idx_ds_compare_config_metric_specific; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_compare_config_metric_specific ON public.ds_compare_config USING btree (system_under_test_id, test_environment, workload, application_dashboard_id, panel_id, metric_name) WHERE (metric_name IS NOT NULL);


--
-- Name: idx_ds_compare_config_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_compare_config_organization_id ON public.ds_compare_config USING btree (organization_id);


--
-- Name: idx_ds_compare_config_panel_specific; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_compare_config_panel_specific ON public.ds_compare_config USING btree (system_under_test_id, test_environment, workload, application_dashboard_id, panel_id) WHERE (metric_name IS NULL);


--
-- Name: idx_ds_compare_config_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_compare_config_team_id ON public.ds_compare_config USING btree (team_id);


--
-- Name: idx_ds_control_group_statistics_application_dashboard_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_group_statistics_application_dashboard_id ON public.ds_control_group_statistics USING btree (application_dashboard_id);


--
-- Name: idx_ds_control_group_statistics_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_group_statistics_composite ON public.ds_control_group_statistics USING btree (control_group_id, application_dashboard_id, panel_id);


--
-- Name: idx_ds_control_group_statistics_control_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_group_statistics_control_group_id ON public.ds_control_group_statistics USING btree (control_group_id);


--
-- Name: idx_ds_control_group_statistics_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_group_statistics_created_by ON public.ds_control_group_statistics USING btree (created_by);


--
-- Name: idx_ds_control_group_statistics_metric_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_group_statistics_metric_name ON public.ds_control_group_statistics USING btree (metric_name);


--
-- Name: idx_ds_control_group_statistics_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_group_statistics_organization_id ON public.ds_control_group_statistics USING btree (organization_id);


--
-- Name: idx_ds_control_group_statistics_panel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_group_statistics_panel_id ON public.ds_control_group_statistics USING btree (panel_id);


--
-- Name: idx_ds_control_group_statistics_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_group_statistics_team_id ON public.ds_control_group_statistics USING btree (team_id);


--
-- Name: idx_ds_control_group_stats_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_ds_control_group_stats_unique ON public.ds_control_group_statistics USING btree (control_group_id, application_dashboard_id, panel_id, metric_name);


--
-- Name: idx_ds_control_groups_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_groups_composite ON public.ds_control_groups USING btree (system_under_test_id, workload, test_environment);


--
-- Name: idx_ds_control_groups_control_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_groups_control_group_id ON public.ds_control_groups USING btree (control_group_id);


--
-- Name: idx_ds_control_groups_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_groups_created_by ON public.ds_control_groups USING btree (created_by);


--
-- Name: idx_ds_control_groups_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_groups_organization_id ON public.ds_control_groups USING btree (organization_id);


--
-- Name: idx_ds_control_groups_system_under_test_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_groups_system_under_test_id ON public.ds_control_groups USING btree (system_under_test_id);


--
-- Name: idx_ds_control_groups_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_groups_team_id ON public.ds_control_groups USING btree (team_id);


--
-- Name: idx_ds_control_groups_test_environment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_groups_test_environment ON public.ds_control_groups USING btree (test_environment);


--
-- Name: idx_ds_control_groups_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_groups_updated_at ON public.ds_control_groups USING btree (updated_at);


--
-- Name: idx_ds_control_groups_workload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_control_groups_workload ON public.ds_control_groups USING btree (workload);


--
-- Name: idx_ds_metric_classification_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_classification_created_by ON public.ds_metric_classification USING btree (created_by);


--
-- Name: idx_ds_metric_classification_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_classification_lookup ON public.ds_metric_classification USING btree (system_under_test_id, test_environment, workload, application_dashboard_id, panel_id, metric_name);


--
-- Name: idx_ds_metric_classification_metric; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_classification_metric ON public.ds_metric_classification USING btree (metric_name) WHERE (metric_name IS NOT NULL);


--
-- Name: idx_ds_metric_classification_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_classification_organization_id ON public.ds_metric_classification USING btree (organization_id);


--
-- Name: idx_ds_metric_classification_panel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_classification_panel ON public.ds_metric_classification USING btree (application_dashboard_id, panel_id);


--
-- Name: idx_ds_metric_classification_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_classification_team_id ON public.ds_metric_classification USING btree (team_id);


--
-- Name: idx_ds_metric_collection_status_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_collection_status_created_by ON public.ds_metric_collection_status USING btree (created_by);


--
-- Name: idx_ds_metric_collection_status_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_collection_status_organization_id ON public.ds_metric_collection_status USING btree (organization_id);


--
-- Name: idx_ds_metric_collection_status_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_collection_status_team_id ON public.ds_metric_collection_status USING btree (team_id);


--
-- Name: idx_ds_metric_statistics_application_dashboard_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_application_dashboard_id ON public.ds_metric_statistics USING btree (application_dashboard_id);


--
-- Name: idx_ds_metric_statistics_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_composite ON public.ds_metric_statistics USING btree (test_run_id, application_dashboard_id, panel_id);


--
-- Name: idx_ds_metric_statistics_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_created_by ON public.ds_metric_statistics USING btree (created_by);


--
-- Name: idx_ds_metric_statistics_dashboard; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_dashboard ON public.ds_metric_statistics USING btree (dashboard_uid, dashboard_label, panel_id);


--
-- Name: idx_ds_metric_statistics_dashboard_label; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_dashboard_label ON public.ds_metric_statistics USING btree (dashboard_label);


--
-- Name: idx_ds_metric_statistics_dashboard_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_dashboard_uid ON public.ds_metric_statistics USING btree (dashboard_uid);


--
-- Name: idx_ds_metric_statistics_metric_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_metric_name ON public.ds_metric_statistics USING btree (metric_name);


--
-- Name: idx_ds_metric_statistics_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_organization_id ON public.ds_metric_statistics USING btree (organization_id);


--
-- Name: idx_ds_metric_statistics_panel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_panel_id ON public.ds_metric_statistics USING btree (panel_id);


--
-- Name: idx_ds_metric_statistics_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_team_id ON public.ds_metric_statistics USING btree (team_id);


--
-- Name: idx_ds_metric_statistics_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_test_run_id ON public.ds_metric_statistics USING btree (test_run_id);


--
-- Name: idx_ds_metric_statistics_test_run_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_test_run_start ON public.ds_metric_statistics USING btree (test_run_start);


--
-- Name: idx_ds_metric_statistics_unit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_statistics_unit ON public.ds_metric_statistics USING btree (unit);


--
-- Name: idx_ds_metric_stats_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_stats_composite ON public.ds_metric_statistics USING btree (application_dashboard_id, panel_id);


--
-- Name: idx_ds_metric_stats_percentiles; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_stats_percentiles ON public.ds_metric_statistics USING gin (percentiles);


--
-- Name: idx_ds_metric_stats_test_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metric_stats_test_run ON public.ds_metric_statistics USING btree (test_run_id);


--
-- Name: idx_ds_metrics_application_dashboard_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_application_dashboard_id ON public.ds_metrics USING btree (application_dashboard_id);


--
-- Name: idx_ds_metrics_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_composite ON public.ds_metrics USING btree (test_run_id, application_dashboard_id, panel_id);


--
-- Name: idx_ds_metrics_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_created_by ON public.ds_metrics USING btree (created_by);


--
-- Name: idx_ds_metrics_dashboard_panel_metric_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_dashboard_panel_metric_time ON public.ds_metrics USING btree (application_dashboard_id, panel_id, metric_name, "time" DESC);


--
-- Name: idx_ds_metrics_metric_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_metric_name ON public.ds_metrics USING btree (metric_name);


--
-- Name: idx_ds_metrics_metric_name_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_metric_name_time ON public.ds_metrics USING btree (metric_name, "time" DESC);


--
-- Name: idx_ds_metrics_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_organization_id ON public.ds_metrics USING btree (organization_id);


--
-- Name: idx_ds_metrics_panel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_panel_id ON public.ds_metrics USING btree (panel_id);


--
-- Name: idx_ds_metrics_panel_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_panel_time ON public.ds_metrics USING btree (panel_id, "time" DESC);


--
-- Name: idx_ds_metrics_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_team_id ON public.ds_metrics USING btree (team_id);


--
-- Name: idx_ds_metrics_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_test_run_id ON public.ds_metrics USING btree (test_run_id);


--
-- Name: idx_ds_metrics_test_run_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_test_run_time ON public.ds_metrics USING btree (test_run_id, "time" DESC);


--
-- Name: idx_ds_metrics_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_time ON public.ds_metrics USING btree ("time");


--
-- Name: idx_ds_metrics_upsert_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_ds_metrics_upsert_key ON public.ds_metrics USING btree (test_run_id, application_dashboard_id, panel_id, metric_name, "time");


--
-- Name: idx_ds_metrics_value; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_metrics_value ON public.ds_metrics USING btree (value);


--
-- Name: idx_ds_panels_application_dashboard_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_panels_application_dashboard_id ON public.ds_panels USING btree (application_dashboard_id);


--
-- Name: idx_ds_panels_benchmark_ids; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_panels_benchmark_ids ON public.ds_panels USING gin (benchmark_ids);


--
-- Name: idx_ds_panels_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_panels_composite ON public.ds_panels USING btree (test_run_id, application_dashboard_id, panel_id);


--
-- Name: idx_ds_panels_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_panels_created_by ON public.ds_panels USING btree (created_by);


--
-- Name: idx_ds_panels_dashboard_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_panels_dashboard_uid ON public.ds_panels USING btree (dashboard_uid);


--
-- Name: idx_ds_panels_datasource_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_panels_datasource_type ON public.ds_panels USING btree (datasource_type);


--
-- Name: idx_ds_panels_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_panels_organization_id ON public.ds_panels USING btree (organization_id);


--
-- Name: idx_ds_panels_panel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_panels_panel_id ON public.ds_panels USING btree (panel_id);


--
-- Name: idx_ds_panels_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_panels_team_id ON public.ds_panels USING btree (team_id);


--
-- Name: idx_ds_panels_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_panels_test_run_id ON public.ds_panels USING btree (test_run_id);


--
-- Name: idx_ds_panels_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_panels_updated_at ON public.ds_panels USING btree (updated_at);


--
-- Name: idx_ds_queries_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_queries_created_by ON public.ds_queries USING btree (created_by);


--
-- Name: idx_ds_queries_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_queries_hash ON public.ds_queries USING btree (query_hash);


--
-- Name: idx_ds_queries_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_queries_organization_id ON public.ds_queries USING btree (organization_id);


--
-- Name: idx_ds_queries_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_queries_source ON public.ds_queries USING btree (source_type, source_instance);


--
-- Name: idx_ds_queries_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_queries_team_id ON public.ds_queries USING btree (team_id);


--
-- Name: idx_ds_query_executions_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_query_executions_created_by ON public.ds_query_executions USING btree (created_by);


--
-- Name: idx_ds_query_executions_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_query_executions_organization_id ON public.ds_query_executions USING btree (organization_id);


--
-- Name: idx_ds_query_executions_query_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_query_executions_query_id ON public.ds_query_executions USING btree (query_id);


--
-- Name: idx_ds_query_executions_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_query_executions_team_id ON public.ds_query_executions USING btree (team_id);


--
-- Name: idx_ds_query_executions_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_query_executions_test_run_id ON public.ds_query_executions USING btree (test_run_id);


--
-- Name: idx_ds_tracked_differences_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_tracked_differences_created_by ON public.ds_tracked_differences USING btree (created_by);


--
-- Name: idx_ds_tracked_differences_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_tracked_differences_organization_id ON public.ds_tracked_differences USING btree (organization_id);


--
-- Name: idx_ds_tracked_differences_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ds_tracked_differences_team_id ON public.ds_tracked_differences USING btree (team_id);


--
-- Name: idx_dynatrace_configs_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_configs_created_by ON public.dynatrace_configs USING btree (created_by);


--
-- Name: idx_dynatrace_configs_host; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_dynatrace_configs_host ON public.dynatrace_configs USING btree (host);


--
-- Name: idx_dynatrace_configs_label; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_configs_label ON public.dynatrace_configs USING btree (label);


--
-- Name: idx_dynatrace_configs_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_configs_organization_id ON public.dynatrace_configs USING btree (organization_id);


--
-- Name: idx_dynatrace_configs_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_configs_team_id ON public.dynatrace_configs USING btree (team_id);


--
-- Name: idx_dynatrace_entity_mappings_config_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_entity_mappings_config_id ON public.dynatrace_entity_mappings USING btree (dynatrace_config_id);


--
-- Name: idx_dynatrace_entity_mappings_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_entity_mappings_created_by ON public.dynatrace_entity_mappings USING btree (created_by);


--
-- Name: idx_dynatrace_entity_mappings_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_entity_mappings_organization_id ON public.dynatrace_entity_mappings USING btree (organization_id);


--
-- Name: idx_dynatrace_entity_mappings_system_level; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_entity_mappings_system_level ON public.dynatrace_entity_mappings USING btree (system_under_test_id, level);


--
-- Name: idx_dynatrace_entity_mappings_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_entity_mappings_team_id ON public.dynatrace_entity_mappings USING btree (team_id);


--
-- Name: idx_dynatrace_entity_mappings_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_dynatrace_entity_mappings_unique ON public.dynatrace_entity_mappings USING btree (system_under_test_id, COALESCE(test_environment, ''::character varying), COALESCE(workload, ''::character varying), entity_id);


--
-- Name: idx_dynatrace_queries_application_dashboard; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_queries_application_dashboard ON public.dynatrace_queries USING btree (application_dashboard_id, dashboard_label);


--
-- Name: idx_dynatrace_queries_config_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_queries_config_id ON public.dynatrace_queries USING btree (dynatrace_config_id);


--
-- Name: idx_dynatrace_queries_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_queries_created_at ON public.dynatrace_queries USING btree (created_at DESC);


--
-- Name: idx_dynatrace_queries_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_queries_created_by ON public.dynatrace_queries USING btree (created_by);


--
-- Name: idx_dynatrace_queries_dashboard_panel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_queries_dashboard_panel ON public.dynatrace_queries USING btree (dashboard_label, panel_title);


--
-- Name: idx_dynatrace_queries_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_queries_organization_id ON public.dynatrace_queries USING btree (organization_id);


--
-- Name: idx_dynatrace_queries_panel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_queries_panel_id ON public.dynatrace_queries USING btree (panel_id);


--
-- Name: idx_dynatrace_queries_system_env_workload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_queries_system_env_workload ON public.dynatrace_queries USING btree (system_under_test_id, test_environment, workload);


--
-- Name: idx_dynatrace_queries_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dynatrace_queries_team_id ON public.dynatrace_queries USING btree (team_id);


--
-- Name: idx_events_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_organization_id ON public.events USING btree (organization_id);


--
-- Name: idx_events_system_env; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_system_env ON public.events USING btree (system_under_test_id, test_environment);


--
-- Name: idx_events_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_timestamp ON public.events USING btree ("timestamp");


--
-- Name: idx_expected_config_changes_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_expected_config_changes_composite ON public.expected_config_changes USING btree (system_under_test_id, test_environment, workload);


--
-- Name: idx_expected_config_changes_config_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_expected_config_changes_config_key ON public.expected_config_changes USING btree (config_key);


--
-- Name: idx_expected_config_changes_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_expected_config_changes_created_by ON public.expected_config_changes USING btree (created_by);


--
-- Name: idx_expected_config_changes_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_expected_config_changes_organization_id ON public.expected_config_changes USING btree (organization_id);


--
-- Name: idx_expected_config_changes_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_expected_config_changes_team_id ON public.expected_config_changes USING btree (team_id);


--
-- Name: idx_generated_reports_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_generated_reports_created_at ON public.generated_reports USING btree (created_at);


--
-- Name: idx_generated_reports_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_generated_reports_created_by ON public.generated_reports USING btree (created_by);


--
-- Name: idx_generated_reports_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_generated_reports_organization_id ON public.generated_reports USING btree (organization_id);


--
-- Name: idx_generated_reports_share_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_generated_reports_share_id ON public.generated_reports USING btree (share_id);


--
-- Name: idx_generated_reports_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_generated_reports_status ON public.generated_reports USING btree (status);


--
-- Name: idx_generated_reports_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_generated_reports_template_id ON public.generated_reports USING btree (template_id);


--
-- Name: idx_generated_reports_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_generated_reports_test_run_id ON public.generated_reports USING btree (test_run_id);


--
-- Name: idx_generic_deep_links_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_generic_deep_links_created_by ON public.generic_deep_links USING btree (created_by);


--
-- Name: idx_generic_deep_links_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_generic_deep_links_organization_id ON public.generic_deep_links USING btree (organization_id);


--
-- Name: idx_generic_deep_links_profile; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_generic_deep_links_profile ON public.generic_deep_links USING btree (profile);


--
-- Name: idx_generic_deep_links_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_generic_deep_links_team_id ON public.generic_deep_links USING btree (team_id);


--
-- Name: idx_grafana_dashboards_grafana_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_dashboards_grafana_id ON public.grafana_dashboards USING btree (grafana_instance_id);


--
-- Name: idx_grafana_dashboards_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_dashboards_name ON public.grafana_dashboards USING btree (name);


--
-- Name: idx_grafana_dashboards_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_dashboards_organization_id ON public.grafana_dashboards USING btree (organization_id);


--
-- Name: idx_grafana_dashboards_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_dashboards_tags ON public.grafana_dashboards USING gin (tags);


--
-- Name: idx_grafana_dashboards_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_dashboards_team_id ON public.grafana_dashboards USING btree (team_id);


--
-- Name: idx_grafana_dashboards_template_profile; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_dashboards_template_profile ON public.grafana_dashboards USING btree (template_profile) WHERE (template_profile IS NOT NULL);


--
-- Name: idx_grafana_dashboards_template_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_dashboards_template_uid ON public.grafana_dashboards USING btree (template_dashboard_uid) WHERE (template_dashboard_uid IS NOT NULL);


--
-- Name: idx_grafana_dashboards_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_dashboards_uid ON public.grafana_dashboards USING btree (uid);


--
-- Name: idx_grafana_dashboards_used_by_sut; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_dashboards_used_by_sut ON public.grafana_dashboards USING gin (used_by_sut);


--
-- Name: idx_grafana_instances_label; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_instances_label ON public.grafana_instances USING btree (label);


--
-- Name: idx_grafana_instances_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_instances_organization_id ON public.grafana_instances USING btree (organization_id);


--
-- Name: idx_grafana_instances_snapshot; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_instances_snapshot ON public.grafana_instances USING btree (snapshot_instance) WHERE (snapshot_instance = true);


--
-- Name: idx_grafana_instances_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grafana_instances_team_id ON public.grafana_instances USING btree (team_id);


--
-- Name: idx_graph_presets_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_graph_presets_created_by ON public.graph_presets USING btree (created_by);


--
-- Name: idx_graph_presets_is_global; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_graph_presets_is_global ON public.graph_presets USING btree (is_global);


--
-- Name: idx_graph_presets_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_graph_presets_name ON public.graph_presets USING btree (name);


--
-- Name: idx_graph_presets_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_graph_presets_organization_id ON public.graph_presets USING btree (organization_id);


--
-- Name: idx_graph_presets_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_graph_presets_team_id ON public.graph_presets USING btree (team_id);


--
-- Name: idx_graph_presets_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_graph_presets_test_run_id ON public.graph_presets USING btree (test_run_id);


--
-- Name: idx_graph_presets_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_graph_presets_user_id ON public.graph_presets USING btree (user_id);


--
-- Name: idx_graph_presets_user_test_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_graph_presets_user_test_run ON public.graph_presets USING btree (user_id, test_run_id);


--
-- Name: idx_notification_channels_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_channels_created_by ON public.notification_channels USING btree (created_by);


--
-- Name: idx_notification_channels_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_channels_enabled ON public.notification_channels USING btree (enabled);


--
-- Name: idx_notification_channels_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_channels_organization_id ON public.notification_channels USING btree (organization_id);


--
-- Name: idx_notification_channels_system_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_channels_system_id ON public.notification_channels USING btree (system_under_test_id);


--
-- Name: idx_notification_channels_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_channels_team_id ON public.notification_channels USING btree (team_id);


--
-- Name: idx_organization_members_org_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organization_members_org_id ON public.organization_members USING btree (organization_id);


--
-- Name: idx_organization_members_org_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organization_members_org_user ON public.organization_members USING btree (organization_id, user_id);


--
-- Name: idx_organization_members_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organization_members_user_id ON public.organization_members USING btree (user_id);


--
-- Name: idx_organizations_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organizations_name ON public.organizations USING btree (name);


--
-- Name: idx_pending_ds_compare_config_changes_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pending_ds_compare_config_changes_created_by ON public.pending_ds_compare_config_changes USING btree (created_by);


--
-- Name: idx_pending_ds_compare_config_changes_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pending_ds_compare_config_changes_organization_id ON public.pending_ds_compare_config_changes USING btree (organization_id);


--
-- Name: idx_pending_ds_compare_config_changes_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pending_ds_compare_config_changes_team_id ON public.pending_ds_compare_config_changes USING btree (team_id);


--
-- Name: idx_profile_benchmarks_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_benchmarks_created_by ON public.profile_benchmarks USING btree (created_by);


--
-- Name: idx_profile_benchmarks_dashboard_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_benchmarks_dashboard_id ON public.profile_benchmarks USING btree (profile_dashboard_id);


--
-- Name: idx_profile_benchmarks_dashboard_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_benchmarks_dashboard_uid ON public.profile_benchmarks USING btree (dashboard_uid);


--
-- Name: idx_profile_benchmarks_org_profile; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_benchmarks_org_profile ON public.profile_benchmarks USING btree (organization_id, profile_id);


--
-- Name: idx_profile_benchmarks_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_benchmarks_organization_id ON public.profile_benchmarks USING btree (organization_id);


--
-- Name: idx_profile_benchmarks_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_benchmarks_profile_id ON public.profile_benchmarks USING btree (profile_id);


--
-- Name: idx_profile_benchmarks_workload_pattern; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_benchmarks_workload_pattern ON public.profile_benchmarks USING btree (workload_pattern);


--
-- Name: idx_profile_dashboards_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_dashboards_created_by ON public.profile_grafana_dashboards USING btree (created_by);


--
-- Name: idx_profile_dashboards_org_profile; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_dashboards_org_profile ON public.profile_grafana_dashboards USING btree (organization_id, profile);


--
-- Name: idx_profile_dashboards_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_dashboards_organization_id ON public.profile_grafana_dashboards USING btree (organization_id);


--
-- Name: idx_profile_grafana_dashboards_dashboard_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_grafana_dashboards_dashboard_uid ON public.profile_grafana_dashboards USING btree (dashboard_uid);


--
-- Name: idx_profile_grafana_dashboards_grafana_label; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_grafana_dashboards_grafana_label ON public.profile_grafana_dashboards USING btree (grafana_label);


--
-- Name: idx_profile_grafana_dashboards_profile; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profile_grafana_dashboards_profile ON public.profile_grafana_dashboards USING btree (profile);


--
-- Name: idx_profiles_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_created_at ON public.profiles USING btree (created_at);


--
-- Name: idx_profiles_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_created_by ON public.profiles USING btree (created_by);


--
-- Name: idx_profiles_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_name ON public.profiles USING btree (name);


--
-- Name: idx_profiles_org_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_org_created ON public.profiles USING btree (organization_id, created_at DESC);


--
-- Name: idx_profiles_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_organization_id ON public.profiles USING btree (organization_id);


--
-- Name: idx_profiles_read_only; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_read_only ON public.profiles USING btree (read_only);


--
-- Name: idx_pyroscope_instances_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pyroscope_instances_created_by ON public.pyroscope_instances USING btree (created_by);


--
-- Name: idx_pyroscope_instances_label; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pyroscope_instances_label ON public.pyroscope_instances USING btree (label);


--
-- Name: idx_pyroscope_instances_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pyroscope_instances_organization_id ON public.pyroscope_instances USING btree (organization_id);


--
-- Name: idx_pyroscope_instances_stand_alone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pyroscope_instances_stand_alone ON public.pyroscope_instances USING btree (pyroscope_stand_alone);


--
-- Name: idx_pyroscope_instances_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pyroscope_instances_team_id ON public.pyroscope_instances USING btree (team_id);


--
-- Name: idx_report_templates_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_report_templates_created_by ON public.report_templates USING btree (created_by);


--
-- Name: idx_report_templates_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_report_templates_organization_id ON public.report_templates USING btree (organization_id);


--
-- Name: idx_report_templates_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_report_templates_team_id ON public.report_templates USING btree (team_id);


--
-- Name: idx_requests_error_test_run_id_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_requests_error_test_run_id_time ON public.requests_error USING btree (test_run_id, "time" DESC);


--
-- Name: idx_requests_error_transaction_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_requests_error_transaction_name ON public.requests_error USING btree (transaction_name);


--
-- Name: idx_requests_error_url_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_requests_error_url_hash ON public.requests_error USING btree (url_hash);


--
-- Name: idx_requests_raw_grouping; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_requests_raw_grouping ON public.requests_raw USING btree (test_run_id, scenario_name, transaction_name, sampler_name, "time");


--
-- Name: idx_requests_raw_scenario_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_requests_raw_scenario_name ON public.requests_raw USING btree (scenario_name) WHERE (scenario_name IS NOT NULL);


--
-- Name: idx_requests_raw_test_run_id_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_requests_raw_test_run_id_time ON public.requests_raw USING btree (test_run_id, "time" DESC);


--
-- Name: idx_requests_raw_test_run_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_requests_raw_test_run_time ON public.requests_raw USING btree (test_run_id, "time");


--
-- Name: idx_requests_raw_transaction_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_requests_raw_transaction_name ON public.requests_raw USING btree (transaction_name) WHERE (transaction_name IS NOT NULL);


--
-- Name: idx_requests_raw_url_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_requests_raw_url_hash ON public.requests_raw USING btree (url_hash);


--
-- Name: idx_systems_under_test_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_systems_under_test_created_by ON public.systems_under_test USING btree (created_by);


--
-- Name: idx_systems_under_test_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_systems_under_test_name ON public.systems_under_test USING btree (name);


--
-- Name: idx_systems_under_test_org_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_systems_under_test_org_created ON public.systems_under_test USING btree (organization_id, created_at DESC);


--
-- Name: idx_systems_under_test_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_systems_under_test_organization_id ON public.systems_under_test USING btree (organization_id);


--
-- Name: idx_systems_under_test_pyroscope_configurations; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_systems_under_test_pyroscope_configurations ON public.systems_under_test USING gin (pyroscope_configurations);


--
-- Name: idx_systems_under_test_pyroscope_instance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_systems_under_test_pyroscope_instance ON public.systems_under_test USING btree (pyroscope_instance_id);


--
-- Name: idx_systems_under_test_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_systems_under_test_team_id ON public.systems_under_test USING btree (team_id);


--
-- Name: idx_team_members_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_team_members_team_id ON public.team_members USING btree (team_id);


--
-- Name: idx_team_members_team_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_team_members_team_user ON public.team_members USING btree (team_id, user_id);


--
-- Name: idx_team_members_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_team_members_user_id ON public.team_members USING btree (user_id);


--
-- Name: idx_teams_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_teams_name ON public.teams USING btree (organization_id, name);


--
-- Name: idx_teams_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_teams_organization_id ON public.teams USING btree (organization_id);


--
-- Name: idx_test_environments_system_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_environments_system_id ON public.system_under_test_test_environments USING btree (system_under_test_id);


--
-- Name: idx_test_run_alerts_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_run_alerts_organization_id ON public.test_run_alerts USING btree (organization_id);


--
-- Name: idx_test_run_alerts_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_run_alerts_test_run_id ON public.test_run_alerts USING btree (test_run_id);


--
-- Name: idx_test_run_configs_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_run_configs_organization_id ON public.test_run_configs USING btree (organization_id);


--
-- Name: idx_test_run_configs_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_run_configs_test_run_id ON public.test_run_configs USING btree (test_run_id);


--
-- Name: idx_test_run_configs_test_run_id_string; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_run_configs_test_run_id_string ON public.test_run_configs USING btree (test_run_id_string);


--
-- Name: idx_test_run_events_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_run_events_organization_id ON public.test_run_events USING btree (organization_id);


--
-- Name: idx_test_run_events_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_run_events_test_run_id ON public.test_run_events USING btree (test_run_id);


--
-- Name: idx_test_runs_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_application_id ON public.test_runs USING btree (system_under_test_id);


--
-- Name: idx_test_runs_completed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_completed ON public.test_runs USING btree (completed);


--
-- Name: idx_test_runs_completed_updated; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_completed_updated ON public.test_runs USING btree (completed, updated_at);


--
-- Name: idx_test_runs_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_composite ON public.test_runs USING btree (system_under_test_id, test_environment, workload);


--
-- Name: idx_test_runs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_created_at ON public.test_runs USING btree (created_at);


--
-- Name: idx_test_runs_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_created_by ON public.test_runs USING btree (created_by);


--
-- Name: idx_test_runs_is_stale; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_is_stale ON public.test_runs USING btree (is_stale);


--
-- Name: idx_test_runs_org_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_org_created ON public.test_runs USING btree (organization_id, created_at DESC);


--
-- Name: idx_test_runs_org_system_env; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_org_system_env ON public.test_runs USING btree (organization_id, system_under_test_id, test_environment);


--
-- Name: idx_test_runs_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_organization_id ON public.test_runs USING btree (organization_id);


--
-- Name: idx_test_runs_system_env_workload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_system_env_workload ON public.test_runs USING btree (system_under_test_id, test_environment, workload);


--
-- Name: idx_test_runs_system_env_workload_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_system_env_workload_created ON public.test_runs USING btree (system_under_test_id, test_environment, workload, created_at);


--
-- Name: idx_test_runs_system_under_test_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_system_under_test_id ON public.test_runs USING btree (system_under_test_id);


--
-- Name: idx_test_runs_test_environment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_test_environment ON public.test_runs USING btree (test_environment);


--
-- Name: idx_test_runs_test_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_test_run_id ON public.test_runs USING btree (test_run_id);


--
-- Name: idx_test_runs_workload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_test_runs_workload ON public.test_runs USING btree (workload);


--
-- Name: idx_tracing_instances_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tracing_instances_created_by ON public.tracing_instances USING btree (created_by);


--
-- Name: idx_tracing_instances_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tracing_instances_organization_id ON public.tracing_instances USING btree (organization_id);


--
-- Name: idx_tracing_instances_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tracing_instances_team_id ON public.tracing_instances USING btree (team_id);


--
-- Name: idx_tracing_instances_url; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tracing_instances_url ON public.tracing_instances USING btree (tracing_url);


--
-- Name: idx_tracing_services_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tracing_services_created_by ON public.tracing_services USING btree (created_by);


--
-- Name: idx_tracing_services_instance_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tracing_services_instance_id ON public.tracing_services USING btree (tracing_instance_id);


--
-- Name: idx_tracing_services_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tracing_services_organization_id ON public.tracing_services USING btree (organization_id);


--
-- Name: idx_tracing_services_system_env; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tracing_services_system_env ON public.tracing_services USING btree (system_under_test_id, test_environment);


--
-- Name: idx_tracing_services_system_env_workload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tracing_services_system_env_workload ON public.tracing_services USING btree (system_under_test_id, test_environment, workload);


--
-- Name: idx_tracing_services_system_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tracing_services_system_id ON public.tracing_services USING btree (system_under_test_id);


--
-- Name: idx_tracing_services_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tracing_services_team_id ON public.tracing_services USING btree (team_id);


--
-- Name: idx_transactions_grouping; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transactions_grouping ON public.transactions USING btree (test_run_id, scenario_name, transaction_name, "time");


--
-- Name: idx_transactions_scenario_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transactions_scenario_name ON public.transactions USING btree (scenario_name) WHERE (scenario_name IS NOT NULL);


--
-- Name: idx_transactions_test_run_id_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transactions_test_run_id_time ON public.transactions USING btree (test_run_id, "time" DESC);


--
-- Name: idx_transactions_test_run_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transactions_test_run_time ON public.transactions USING btree (test_run_id, "time");


--
-- Name: idx_transactions_transaction_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transactions_transaction_name ON public.transactions USING btree (transaction_name);


--
-- Name: idx_trends_filter_presets_app_dashboard; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trends_filter_presets_app_dashboard ON public.trends_filter_presets USING btree (application_dashboard_id) WHERE (application_dashboard_id IS NOT NULL);


--
-- Name: idx_trends_filter_presets_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trends_filter_presets_created_by ON public.trends_filter_presets USING btree (created_by);


--
-- Name: idx_trends_filter_presets_created_for_test_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trends_filter_presets_created_for_test_run ON public.trends_filter_presets USING btree (created_for_test_run_id) WHERE (created_for_test_run_id IS NOT NULL);


--
-- Name: idx_trends_filter_presets_global; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trends_filter_presets_global ON public.trends_filter_presets USING btree (is_global);


--
-- Name: idx_trends_filter_presets_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trends_filter_presets_name ON public.trends_filter_presets USING btree (name);


--
-- Name: idx_trends_filter_presets_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trends_filter_presets_organization_id ON public.trends_filter_presets USING btree (organization_id);


--
-- Name: idx_trends_filter_presets_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trends_filter_presets_team_id ON public.trends_filter_presets USING btree (team_id);


--
-- Name: idx_trends_filter_presets_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trends_filter_presets_type ON public.trends_filter_presets USING btree (preset_type);


--
-- Name: idx_url_patterns_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_url_patterns_created_by ON public.url_patterns USING btree (created_by);


--
-- Name: idx_url_patterns_normalized_url; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_url_patterns_normalized_url ON public.url_patterns USING btree (normalized_url);


--
-- Name: idx_url_patterns_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_url_patterns_organization_id ON public.url_patterns USING btree (organization_id);


--
-- Name: idx_url_patterns_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_url_patterns_team_id ON public.url_patterns USING btree (team_id);


--
-- Name: idx_virtual_users_test_run_id_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_virtual_users_test_run_id_time ON public.virtual_users USING btree (test_run_id, "time" DESC);


--
-- Name: idx_workload_apdex_environment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_apdex_environment ON public.workload_apdex_thresholds USING btree (test_environment);


--
-- Name: idx_workload_apdex_system; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_apdex_system ON public.workload_apdex_thresholds USING btree (system_under_test_id);


--
-- Name: idx_workload_apdex_thresholds_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_apdex_thresholds_created_by ON public.workload_apdex_thresholds USING btree (created_by);


--
-- Name: idx_workload_apdex_thresholds_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_apdex_thresholds_organization_id ON public.workload_apdex_thresholds USING btree (organization_id);


--
-- Name: idx_workload_apdex_thresholds_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_apdex_thresholds_team_id ON public.workload_apdex_thresholds USING btree (team_id);


--
-- Name: idx_workload_apdex_workload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_apdex_workload ON public.workload_apdex_thresholds USING btree (workload);


--
-- Name: idx_workload_trans_apdex_environment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_trans_apdex_environment ON public.workload_transaction_apdex_thresholds USING btree (test_environment);


--
-- Name: idx_workload_trans_apdex_system; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_trans_apdex_system ON public.workload_transaction_apdex_thresholds USING btree (system_under_test_id);


--
-- Name: idx_workload_trans_apdex_transaction; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_trans_apdex_transaction ON public.workload_transaction_apdex_thresholds USING btree (transaction_name);


--
-- Name: idx_workload_trans_apdex_workload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_trans_apdex_workload ON public.workload_transaction_apdex_thresholds USING btree (workload);


--
-- Name: idx_workload_transaction_apdex_thresholds_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_transaction_apdex_thresholds_created_by ON public.workload_transaction_apdex_thresholds USING btree (created_by);


--
-- Name: idx_workload_transaction_apdex_thresholds_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_transaction_apdex_thresholds_organization_id ON public.workload_transaction_apdex_thresholds USING btree (organization_id);


--
-- Name: idx_workload_transaction_apdex_thresholds_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workload_transaction_apdex_thresholds_team_id ON public.workload_transaction_apdex_thresholds USING btree (team_id);


--
-- Name: idx_workloads_environment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workloads_environment_id ON public.system_under_test_workloads USING btree (system_under_test_test_environment_id);


--
-- Name: requests_error_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX requests_error_time_idx ON public.requests_error USING btree ("time" DESC);


--
-- Name: requests_raw_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX requests_raw_time_idx ON public.requests_raw USING btree ("time" DESC);


--
-- Name: transactions_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transactions_time_idx ON public.transactions USING btree ("time" DESC);


--
-- Name: uniq_ds_compare_config_metric; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uniq_ds_compare_config_metric ON public.ds_compare_config USING btree (system_under_test_id, test_environment, workload, application_dashboard_id, panel_id, metric_name) WHERE (metric_name IS NOT NULL);


--
-- Name: uniq_ds_compare_config_panel; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uniq_ds_compare_config_panel ON public.ds_compare_config USING btree (system_under_test_id, test_environment, workload, application_dashboard_id, panel_id) WHERE (metric_name IS NULL);


--
-- Name: uq_collection_status; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_collection_status ON public.ds_metric_collection_status USING btree (test_run_id, source_type, source_id);


--
-- Name: virtual_users_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX virtual_users_time_idx ON public.virtual_users USING btree ("time" DESC);


--
-- Name: ds_adapt_results auto_mark_fresh_on_analysis; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER auto_mark_fresh_on_analysis BEFORE INSERT OR UPDATE ON public.ds_adapt_results FOR EACH ROW EXECUTE FUNCTION public.mark_results_fresh_on_analysis();


--
-- Name: ds_compare_config trigger_mark_stale_on_config_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_mark_stale_on_config_update AFTER UPDATE ON public.ds_compare_config FOR EACH ROW EXECUTE FUNCTION public.mark_results_stale_on_config_change();


--
-- Name: dynatrace_queries trigger_update_dynatrace_queries_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_dynatrace_queries_updated_at BEFORE UPDATE ON public.dynatrace_queries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: graph_presets trigger_update_graph_presets_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_graph_presets_updated_at BEFORE UPDATE ON public.graph_presets FOR EACH ROW EXECUTE FUNCTION public.update_graph_presets_updated_at();


--
-- Name: api_keys update_api_keys_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_api_keys_updated_at BEFORE UPDATE ON public.api_keys FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: application_dashboards update_application_dashboards_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_application_dashboards_updated_at BEFORE UPDATE ON public.application_dashboards FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: systems_under_test update_applications_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_applications_updated_at BEFORE UPDATE ON public.systems_under_test FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: profile_grafana_dashboards update_auto_config_grafana_dashboards_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_auto_config_grafana_dashboards_updated_at BEFORE UPDATE ON public.profile_grafana_dashboards FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: benchmarks update_benchmarks_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_benchmarks_updated_at BEFORE UPDATE ON public.benchmarks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: check_results update_check_results_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_check_results_updated_at BEFORE UPDATE ON public.check_results FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: compare_filter_presets update_compare_filter_presets_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_compare_filter_presets_updated_at BEFORE UPDATE ON public.compare_filter_presets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: configuration update_configuration_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_configuration_updated_at BEFORE UPDATE ON public.configuration FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: data_sources update_data_sources_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_data_sources_updated_at BEFORE UPDATE ON public.data_sources FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: ds_compare_config update_ds_compare_config_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ds_compare_config_updated_at BEFORE UPDATE ON public.ds_compare_config FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: ds_control_groups update_ds_control_groups_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ds_control_groups_updated_at BEFORE UPDATE ON public.ds_control_groups FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: ds_panels update_ds_panels_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ds_panels_updated_at BEFORE UPDATE ON public.ds_panels FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: ds_queries update_ds_queries_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ds_queries_updated_at BEFORE UPDATE ON public.ds_queries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: profile_benchmarks update_generic_checks_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_generic_checks_updated_at BEFORE UPDATE ON public.profile_benchmarks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: generic_deep_links update_generic_deep_links_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_generic_deep_links_updated_at BEFORE UPDATE ON public.generic_deep_links FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: grafana_instances update_grafana_instances_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_grafana_instances_updated_at BEFORE UPDATE ON public.grafana_instances FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: graph_presets update_graph_preset_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_graph_preset_modtime BEFORE UPDATE ON public.graph_presets FOR EACH ROW EXECUTE FUNCTION public.update_graph_preset_timestamp();


--
-- Name: licenses update_licenses_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_licenses_updated_at BEFORE UPDATE ON public.licenses FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: organizations update_organizations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_organizations_updated_at BEFORE UPDATE ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: teams update_teams_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_teams_updated_at BEFORE UPDATE ON public.teams FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: test_runs update_test_runs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_test_runs_updated_at BEFORE UPDATE ON public.test_runs FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: tracing_instances update_tracing_instance_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_tracing_instance_modtime BEFORE UPDATE ON public.tracing_instances FOR EACH ROW EXECUTE FUNCTION public.update_tracing_instance_timestamp();


--
-- Name: tracing_services update_tracing_service_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_tracing_service_modtime BEFORE UPDATE ON public.tracing_services FOR EACH ROW EXECUTE FUNCTION public.update_tracing_service_timestamp();


--
-- Name: trends_filter_presets update_trends_filter_presets_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_trends_filter_presets_updated_at BEFORE UPDATE ON public.trends_filter_presets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: workload_apdex_thresholds update_workload_apdex_threshold_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_workload_apdex_threshold_modtime BEFORE UPDATE ON public.workload_apdex_thresholds FOR EACH ROW EXECUTE FUNCTION public.update_workload_apdex_threshold_timestamp();


--
-- Name: workload_transaction_apdex_thresholds update_workload_transaction_apdex_threshold_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_workload_transaction_apdex_threshold_modtime BEFORE UPDATE ON public.workload_transaction_apdex_thresholds FOR EACH ROW EXECUTE FUNCTION public.update_workload_transaction_apdex_threshold_timestamp();


--
-- Name: benchmarks validate_benchmark_configuration_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validate_benchmark_configuration_trigger BEFORE INSERT OR UPDATE ON public.benchmarks FOR EACH ROW EXECUTE FUNCTION public.validate_benchmark_configuration();


--
-- Name: awr_analysis FK_045adf06d3cbb76f0953eb7f516; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awr_analysis
    ADD CONSTRAINT "FK_045adf06d3cbb76f0953eb7f516" FOREIGN KEY (awr_report_id) REFERENCES public.awr_reports(id) ON DELETE CASCADE;


--
-- Name: test_run_configs FK_0f51a7f49362c67adfaaca3973c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_run_configs
    ADD CONSTRAINT "FK_0f51a7f49362c67adfaaca3973c" FOREIGN KEY (test_run_id) REFERENCES public.test_runs(id);


--
-- Name: awr_analysis FK_15edf7debf4435fff131edbff22; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awr_analysis
    ADD CONSTRAINT "FK_15edf7debf4435fff131edbff22" FOREIGN KEY (baseline_report_id) REFERENCES public.awr_reports(id) ON DELETE SET NULL;


--
-- Name: ds_compare_config FK_169495604b63cc277a90ada81f8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_compare_config
    ADD CONSTRAINT "FK_169495604b63cc277a90ada81f8" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id) ON DELETE CASCADE;


--
-- Name: generated_reports FK_2b450ddff1606e922d7a7ea8eba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generated_reports
    ADD CONSTRAINT "FK_2b450ddff1606e922d7a7ea8eba" FOREIGN KEY (template_id) REFERENCES public.report_templates(id) ON DELETE SET NULL;


--
-- Name: benchmarks FK_2e765498731db929f6c706dc4ab; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benchmarks
    ADD CONSTRAINT "FK_2e765498731db929f6c706dc4ab" FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id);


--
-- Name: ds_metric_statistics FK_30d5e9b699656dce6b211718780; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_metric_statistics
    ADD CONSTRAINT "FK_30d5e9b699656dce6b211718780" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id);


--
-- Name: trends_filter_presets FK_40f749c7a9543b7321b4e7bd66a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trends_filter_presets
    ADD CONSTRAINT "FK_40f749c7a9543b7321b4e7bd66a" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id) ON DELETE SET NULL;


--
-- Name: ds_metric_statistics FK_4a9d5323858b5384aa148f1c558; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_metric_statistics
    ADD CONSTRAINT "FK_4a9d5323858b5384aa148f1c558" FOREIGN KEY (benchmark_id) REFERENCES public.benchmarks(id) ON DELETE SET NULL;


--
-- Name: ds_tracked_differences FK_4d91142e1d4b18c2ea87ea4677a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_tracked_differences
    ADD CONSTRAINT "FK_4d91142e1d4b18c2ea87ea4677a" FOREIGN KEY (benchmark_id) REFERENCES public.benchmarks(id) ON DELETE SET NULL;


--
-- Name: expected_config_changes FK_5377cc526fcd0414d88b00cd800; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expected_config_changes
    ADD CONSTRAINT "FK_5377cc526fcd0414d88b00cd800" FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: notification_channels FK_5950c33a12a87b85beaff4a4309; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_channels
    ADD CONSTRAINT "FK_5950c33a12a87b85beaff4a4309" FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: ds_metric_classification FK_5b8c0dc266cea368bc3667ff44d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_metric_classification
    ADD CONSTRAINT "FK_5b8c0dc266cea368bc3667ff44d" FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id);


--
-- Name: profile_benchmarks FK_66596faeada1a3bfed1dbe11d8b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profile_benchmarks
    ADD CONSTRAINT "FK_66596faeada1a3bfed1dbe11d8b" FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: awr_reports FK_6853d313bd41a1264d6a86040da; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awr_reports
    ADD CONSTRAINT "FK_6853d313bd41a1264d6a86040da" FOREIGN KEY (test_run_id) REFERENCES public.test_runs(id) ON DELETE CASCADE;


--
-- Name: dynatrace_entity_mappings FK_68df738bf2244df30125356b0ea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynatrace_entity_mappings
    ADD CONSTRAINT "FK_68df738bf2244df30125356b0ea" FOREIGN KEY (dynatrace_config_id) REFERENCES public.dynatrace_configs(id);


--
-- Name: ds_metrics FK_6b21df61b6b75801a94435590ab; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_metrics
    ADD CONSTRAINT "FK_6b21df61b6b75801a94435590ab" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id);


--
-- Name: ds_tracked_differences FK_851c0133b601de9f6da6929412e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_tracked_differences
    ADD CONSTRAINT "FK_851c0133b601de9f6da6929412e" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id);


--
-- Name: ds_metric_collection_status FK_8cf5fb59cd4aee727bd710ac576; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_metric_collection_status
    ADD CONSTRAINT "FK_8cf5fb59cd4aee727bd710ac576" FOREIGN KEY (test_run_id) REFERENCES public.test_runs(test_run_id);


--
-- Name: benchmarks FK_9864637f3b46c65b330edc79cd0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benchmarks
    ADD CONSTRAINT "FK_9864637f3b46c65b330edc79cd0" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id) ON DELETE CASCADE;


--
-- Name: ds_adapt_results FK_9c5b59c0ddb755948ca90342f9b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_adapt_results
    ADD CONSTRAINT "FK_9c5b59c0ddb755948ca90342f9b" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id);


--
-- Name: ds_adapt_tracked_results FK_a5e858a62af3db24bf4df5c77b5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_adapt_tracked_results
    ADD CONSTRAINT "FK_a5e858a62af3db24bf4df5c77b5" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id);


--
-- Name: application_dashboards FK_a7b2d4a5425c8e087ab8014e3f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dashboards
    ADD CONSTRAINT "FK_a7b2d4a5425c8e087ab8014e3f0" FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id);


--
-- Name: dynatrace_queries FK_ade89d9eddfbfd6a18e3d291de0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynatrace_queries
    ADD CONSTRAINT "FK_ade89d9eddfbfd6a18e3d291de0" FOREIGN KEY (dynatrace_config_id) REFERENCES public.dynatrace_configs(id);


--
-- Name: compare_filter_presets FK_b1aef8d4becaadc9900652373ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.compare_filter_presets
    ADD CONSTRAINT "FK_b1aef8d4becaadc9900652373ed" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id) ON DELETE SET NULL;


--
-- Name: systems_under_test FK_c484c42f239c97e78521f5d4e0b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.systems_under_test
    ADD CONSTRAINT "FK_c484c42f239c97e78521f5d4e0b" FOREIGN KEY (pyroscope_instance_id) REFERENCES public.pyroscope_instances(id);


--
-- Name: test_runs FK_c605af6aaa53c4e55cc4a9a8129; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_runs
    ADD CONSTRAINT "FK_c605af6aaa53c4e55cc4a9a8129" FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id);


--
-- Name: ds_compare_config FK_d0fffa8aa350c854beada004588; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_compare_config
    ADD CONSTRAINT "FK_d0fffa8aa350c854beada004588" FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id);


--
-- Name: tracing_services FK_d47b7bb48b926b2f7f6b9a2399e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracing_services
    ADD CONSTRAINT "FK_d47b7bb48b926b2f7f6b9a2399e" FOREIGN KEY (tracing_instance_id) REFERENCES public.tracing_instances(id) ON DELETE CASCADE;


--
-- Name: ds_metric_classification FK_d49cd20cc90d3ae50c9e158dd8a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_metric_classification
    ADD CONSTRAINT "FK_d49cd20cc90d3ae50c9e158dd8a" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id);


--
-- Name: grafana_dashboards FK_d7c24e2aad8410112f1fd6785e3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grafana_dashboards
    ADD CONSTRAINT "FK_d7c24e2aad8410112f1fd6785e3" FOREIGN KEY (grafana_instance_id) REFERENCES public.grafana_instances(id);


--
-- Name: tracing_services FK_dc58a9f80e04fa36ab4748679cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracing_services
    ADD CONSTRAINT "FK_dc58a9f80e04fa36ab4748679cc" FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: generated_reports FK_e4ebf8a400eca8ab9aa68de4e4a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generated_reports
    ADD CONSTRAINT "FK_e4ebf8a400eca8ab9aa68de4e4a" FOREIGN KEY (test_run_id) REFERENCES public.test_runs(id) ON DELETE CASCADE;


--
-- Name: systems_under_test FK_e59618bddfe1560db0cbe22afc5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.systems_under_test
    ADD CONSTRAINT "FK_e59618bddfe1560db0cbe22afc5" FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE SET NULL;


--
-- Name: ds_control_group_statistics FK_e5aa4997444874424b57320cbff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_control_group_statistics
    ADD CONSTRAINT "FK_e5aa4997444874424b57320cbff" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id);


--
-- Name: application_dashboards FK_e7b0832c5e9bb206704c511f29c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dashboards
    ADD CONSTRAINT "FK_e7b0832c5e9bb206704c511f29c" FOREIGN KEY (grafana_instance_id) REFERENCES public.grafana_instances(id);


--
-- Name: ds_panels FK_ecec1d3e64d45e63e6dcf31daeb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_panels
    ADD CONSTRAINT "FK_ecec1d3e64d45e63e6dcf31daeb" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id);


--
-- Name: events FK_events_system_under_test; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT "FK_events_system_under_test" FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: ds_change_points FK_f1a49042a6e99e2c681a168fbd2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_change_points
    ADD CONSTRAINT "FK_f1a49042a6e99e2c681a168fbd2" FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id);


--
-- Name: application_dashboards FK_fbae9e222dde1d3850c895dc5aa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dashboards
    ADD CONSTRAINT "FK_fbae9e222dde1d3850c895dc5aa" FOREIGN KEY (grafana_dashboard_id) REFERENCES public.grafana_dashboards(id);


--
-- Name: teams FK_fdc736f761896ccc179c823a785; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT "FK_fdc736f761896ccc179c823a785" FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: application_dashboards application_dashboards_grafana_dashboard_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dashboards
    ADD CONSTRAINT application_dashboards_grafana_dashboard_id_fkey FOREIGN KEY (grafana_dashboard_id) REFERENCES public.grafana_dashboards(id) ON DELETE CASCADE;


--
-- Name: application_dashboards application_dashboards_grafana_instance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dashboards
    ADD CONSTRAINT application_dashboards_grafana_instance_id_fkey FOREIGN KEY (grafana_instance_id) REFERENCES public.grafana_instances(id) ON DELETE CASCADE;


--
-- Name: application_dashboards application_dashboards_system_under_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dashboards
    ADD CONSTRAINT application_dashboards_system_under_test_id_fkey FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: systems_under_test applications_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.systems_under_test
    ADD CONSTRAINT applications_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: benchmarks benchmarks_system_under_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benchmarks
    ADD CONSTRAINT benchmarks_system_under_test_id_fkey FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: check_results check_results_system_under_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_results
    ADD CONSTRAINT check_results_system_under_test_id_fkey FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: compare_filter_presets compare_filter_presets_application_dashboard_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.compare_filter_presets
    ADD CONSTRAINT compare_filter_presets_application_dashboard_id_fkey FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id) ON DELETE SET NULL;


--
-- Name: data_sources data_sources_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_sources
    ADD CONSTRAINT data_sources_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: deep_links deep_links_system_under_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deep_links
    ADD CONSTRAINT deep_links_system_under_test_id_fkey FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: deep_links deep_links_template_deep_link_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deep_links
    ADD CONSTRAINT deep_links_template_deep_link_id_fkey FOREIGN KEY (template_deep_link_id) REFERENCES public.generic_deep_links(id);


--
-- Name: ds_query_executions ds_query_executions_query_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_query_executions
    ADD CONSTRAINT ds_query_executions_query_id_fkey FOREIGN KEY (query_id) REFERENCES public.ds_queries(id) ON DELETE CASCADE;


--
-- Name: ds_query_executions ds_query_executions_test_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_query_executions
    ADD CONSTRAINT ds_query_executions_test_run_id_fkey FOREIGN KEY (test_run_id) REFERENCES public.test_runs(id);


--
-- Name: ds_tracked_differences ds_tracked_differences_test_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_tracked_differences
    ADD CONSTRAINT ds_tracked_differences_test_run_id_fkey FOREIGN KEY (test_run_id) REFERENCES public.test_runs(id);


--
-- Name: expected_config_changes expected_config_changes_system_under_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expected_config_changes
    ADD CONSTRAINT expected_config_changes_system_under_test_id_fkey FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: api_keys fk_api_keys_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT fk_api_keys_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: application_dashboards fk_application_dashboards_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dashboards
    ADD CONSTRAINT fk_application_dashboards_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: application_dashboards fk_application_dashboards_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dashboards
    ADD CONSTRAINT fk_application_dashboards_team FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE SET NULL;


--
-- Name: awr_analysis fk_awr_analysis_awr_report; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awr_analysis
    ADD CONSTRAINT fk_awr_analysis_awr_report FOREIGN KEY (awr_report_id) REFERENCES public.awr_reports(id) ON DELETE CASCADE;


--
-- Name: awr_analysis fk_awr_analysis_baseline_report; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awr_analysis
    ADD CONSTRAINT fk_awr_analysis_baseline_report FOREIGN KEY (baseline_report_id) REFERENCES public.awr_reports(id) ON DELETE SET NULL;


--
-- Name: awr_reports fk_awr_reports_test_run; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awr_reports
    ADD CONSTRAINT fk_awr_reports_test_run FOREIGN KEY (test_run_id) REFERENCES public.test_runs(id) ON DELETE CASCADE;


--
-- Name: ds_compare_config fk_ds_compare_config_application_dashboard; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_compare_config
    ADD CONSTRAINT fk_ds_compare_config_application_dashboard FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id) ON DELETE CASCADE;


--
-- Name: ds_compare_config fk_ds_compare_config_system_under_test; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ds_compare_config
    ADD CONSTRAINT fk_ds_compare_config_system_under_test FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id);


--
-- Name: dynatrace_entity_mappings fk_dynatrace_entity_mappings_config; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynatrace_entity_mappings
    ADD CONSTRAINT fk_dynatrace_entity_mappings_config FOREIGN KEY (dynatrace_config_id) REFERENCES public.dynatrace_configs(id) ON DELETE CASCADE;


--
-- Name: dynatrace_entity_mappings fk_dynatrace_entity_mappings_system; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynatrace_entity_mappings
    ADD CONSTRAINT fk_dynatrace_entity_mappings_system FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: dynatrace_queries fk_dynatrace_queries_config; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynatrace_queries
    ADD CONSTRAINT fk_dynatrace_queries_config FOREIGN KEY (dynatrace_config_id) REFERENCES public.dynatrace_configs(id) ON DELETE CASCADE;


--
-- Name: generated_reports fk_generated_reports_template; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generated_reports
    ADD CONSTRAINT fk_generated_reports_template FOREIGN KEY (template_id) REFERENCES public.report_templates(id) ON DELETE SET NULL;


--
-- Name: generated_reports fk_generated_reports_test_run; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generated_reports
    ADD CONSTRAINT fk_generated_reports_test_run FOREIGN KEY (test_run_id) REFERENCES public.test_runs(id) ON DELETE CASCADE;


--
-- Name: grafana_dashboards fk_grafana_dashboards_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grafana_dashboards
    ADD CONSTRAINT fk_grafana_dashboards_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: grafana_dashboards fk_grafana_dashboards_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grafana_dashboards
    ADD CONSTRAINT fk_grafana_dashboards_team FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE SET NULL;


--
-- Name: grafana_instances fk_grafana_instances_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grafana_instances
    ADD CONSTRAINT fk_grafana_instances_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: grafana_instances fk_grafana_instances_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grafana_instances
    ADD CONSTRAINT fk_grafana_instances_team FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE SET NULL;


--
-- Name: notification_channels fk_notification_channels_system_under_test; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_channels
    ADD CONSTRAINT fk_notification_channels_system_under_test FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: organization_members fk_organization_members_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_members
    ADD CONSTRAINT fk_organization_members_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: profile_benchmarks fk_profile_benchmarks_profile; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profile_benchmarks
    ADD CONSTRAINT fk_profile_benchmarks_profile FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: systems_under_test fk_systems_under_test_pyroscope_instance; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.systems_under_test
    ADD CONSTRAINT fk_systems_under_test_pyroscope_instance FOREIGN KEY (pyroscope_instance_id) REFERENCES public.pyroscope_instances(id) ON DELETE SET NULL;


--
-- Name: team_members fk_team_members_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT fk_team_members_team FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE CASCADE;


--
-- Name: tracing_services fk_tracing_services_instance; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracing_services
    ADD CONSTRAINT fk_tracing_services_instance FOREIGN KEY (tracing_instance_id) REFERENCES public.tracing_instances(id) ON DELETE CASCADE;


--
-- Name: tracing_services fk_tracing_services_system_under_test; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracing_services
    ADD CONSTRAINT fk_tracing_services_system_under_test FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: grafana_dashboards grafana_dashboards_grafana_instance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grafana_dashboards
    ADD CONSTRAINT grafana_dashboards_grafana_instance_id_fkey FOREIGN KEY (grafana_instance_id) REFERENCES public.grafana_instances(id) ON DELETE CASCADE;


--
-- Name: pending_ds_compare_config_changes pending_ds_compare_config_changes_ds_compare_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pending_ds_compare_config_changes
    ADD CONSTRAINT pending_ds_compare_config_changes_ds_compare_config_id_fkey FOREIGN KEY (ds_compare_config_id) REFERENCES public.ds_compare_config(id) ON DELETE CASCADE;


--
-- Name: system_under_test_test_environments system_under_test_test_environments_system_under_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_under_test_test_environments
    ADD CONSTRAINT system_under_test_test_environments_system_under_test_id_fkey FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id) ON DELETE CASCADE;


--
-- Name: system_under_test_workloads system_under_test_test_types_system_under_test_test_environment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_under_test_workloads
    ADD CONSTRAINT system_under_test_test_types_system_under_test_test_environment FOREIGN KEY (system_under_test_test_environment_id) REFERENCES public.system_under_test_test_environments(id) ON DELETE CASCADE;


--
-- Name: teams teams_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: test_run_alerts test_run_alerts_test_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_run_alerts
    ADD CONSTRAINT test_run_alerts_test_run_id_fkey FOREIGN KEY (test_run_id) REFERENCES public.test_runs(id) ON DELETE CASCADE;


--
-- Name: test_run_configs test_run_configs_test_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_run_configs
    ADD CONSTRAINT test_run_configs_test_run_id_fkey FOREIGN KEY (test_run_id) REFERENCES public.test_runs(id) ON DELETE CASCADE;


--
-- Name: test_run_events test_run_events_test_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_run_events
    ADD CONSTRAINT test_run_events_test_run_id_fkey FOREIGN KEY (test_run_id) REFERENCES public.test_runs(id) ON DELETE CASCADE;


--
-- Name: test_runs test_runs_system_under_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_runs
    ADD CONSTRAINT test_runs_system_under_test_id_fkey FOREIGN KEY (system_under_test_id) REFERENCES public.systems_under_test(id);


--
-- Name: trends_filter_presets trends_filter_presets_application_dashboard_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trends_filter_presets
    ADD CONSTRAINT trends_filter_presets_application_dashboard_id_fkey FOREIGN KEY (application_dashboard_id) REFERENCES public.application_dashboards(id) ON DELETE SET NULL;


--
-- Name: api_keys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

--
-- Name: application_dashboards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.application_dashboards ENABLE ROW LEVEL SECURITY;

--
-- Name: benchmarks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.benchmarks ENABLE ROW LEVEL SECURITY;

--
-- Name: check_results; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.check_results ENABLE ROW LEVEL SECURITY;

--
-- Name: compare_filter_presets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.compare_filter_presets ENABLE ROW LEVEL SECURITY;

--
-- Name: deep_links; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.deep_links ENABLE ROW LEVEL SECURITY;

--
-- Name: dynatrace_configs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.dynatrace_configs ENABLE ROW LEVEL SECURITY;

--
-- Name: dynatrace_entity_mappings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.dynatrace_entity_mappings ENABLE ROW LEVEL SECURITY;

--
-- Name: dynatrace_queries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.dynatrace_queries ENABLE ROW LEVEL SECURITY;

--
-- Name: events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

--
-- Name: expected_config_changes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.expected_config_changes ENABLE ROW LEVEL SECURITY;

--
-- Name: generated_reports; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.generated_reports ENABLE ROW LEVEL SECURITY;

--
-- Name: generic_deep_links; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.generic_deep_links ENABLE ROW LEVEL SECURITY;

--
-- Name: grafana_dashboards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.grafana_dashboards ENABLE ROW LEVEL SECURITY;

--
-- Name: grafana_instances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.grafana_instances ENABLE ROW LEVEL SECURITY;

--
-- Name: graph_presets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.graph_presets ENABLE ROW LEVEL SECURITY;

--
-- Name: notification_channels; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notification_channels ENABLE ROW LEVEL SECURITY;

--
-- Name: profile_benchmarks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profile_benchmarks ENABLE ROW LEVEL SECURITY;

--
-- Name: profile_grafana_dashboards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profile_grafana_dashboards ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: pyroscope_instances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pyroscope_instances ENABLE ROW LEVEL SECURITY;

--
-- Name: report_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.report_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: api_keys rls_api_keys_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_api_keys_delete ON public.api_keys FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: api_keys rls_api_keys_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_api_keys_insert ON public.api_keys FOR INSERT WITH CHECK (true);


--
-- Name: api_keys rls_api_keys_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_api_keys_select ON public.api_keys FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: api_keys rls_api_keys_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_api_keys_update ON public.api_keys FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: application_dashboards rls_application_dashboards_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_application_dashboards_delete ON public.application_dashboards FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: application_dashboards rls_application_dashboards_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_application_dashboards_insert ON public.application_dashboards FOR INSERT WITH CHECK (true);


--
-- Name: application_dashboards rls_application_dashboards_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_application_dashboards_select ON public.application_dashboards FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: application_dashboards rls_application_dashboards_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_application_dashboards_update ON public.application_dashboards FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: benchmarks rls_benchmarks_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_benchmarks_delete ON public.benchmarks FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: benchmarks rls_benchmarks_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_benchmarks_insert ON public.benchmarks FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: benchmarks rls_benchmarks_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_benchmarks_select ON public.benchmarks FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: benchmarks rls_benchmarks_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_benchmarks_update ON public.benchmarks FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: compare_filter_presets rls_compare_filter_presets_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_compare_filter_presets_delete ON public.compare_filter_presets FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: compare_filter_presets rls_compare_filter_presets_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_compare_filter_presets_insert ON public.compare_filter_presets FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: compare_filter_presets rls_compare_filter_presets_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_compare_filter_presets_select ON public.compare_filter_presets FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: compare_filter_presets rls_compare_filter_presets_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_compare_filter_presets_update ON public.compare_filter_presets FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: deep_links rls_deep_links_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_deep_links_delete ON public.deep_links FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: deep_links rls_deep_links_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_deep_links_insert ON public.deep_links FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: deep_links rls_deep_links_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_deep_links_select ON public.deep_links FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: deep_links rls_deep_links_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_deep_links_update ON public.deep_links FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: dynatrace_configs rls_dynatrace_configs_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_dynatrace_configs_delete ON public.dynatrace_configs FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: dynatrace_configs rls_dynatrace_configs_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_dynatrace_configs_insert ON public.dynatrace_configs FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: dynatrace_configs rls_dynatrace_configs_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_dynatrace_configs_select ON public.dynatrace_configs FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: dynatrace_configs rls_dynatrace_configs_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_dynatrace_configs_update ON public.dynatrace_configs FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: dynatrace_entity_mappings rls_dynatrace_entity_mappings_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_dynatrace_entity_mappings_delete ON public.dynatrace_entity_mappings FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: dynatrace_entity_mappings rls_dynatrace_entity_mappings_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_dynatrace_entity_mappings_insert ON public.dynatrace_entity_mappings FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: dynatrace_entity_mappings rls_dynatrace_entity_mappings_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_dynatrace_entity_mappings_select ON public.dynatrace_entity_mappings FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: dynatrace_entity_mappings rls_dynatrace_entity_mappings_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_dynatrace_entity_mappings_update ON public.dynatrace_entity_mappings FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: dynatrace_queries rls_dynatrace_queries_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_dynatrace_queries_delete ON public.dynatrace_queries FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: dynatrace_queries rls_dynatrace_queries_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_dynatrace_queries_insert ON public.dynatrace_queries FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: dynatrace_queries rls_dynatrace_queries_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_dynatrace_queries_select ON public.dynatrace_queries FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: dynatrace_queries rls_dynatrace_queries_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_dynatrace_queries_update ON public.dynatrace_queries FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: events rls_events_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_events_delete ON public.events FOR DELETE USING ((public.is_global_admin() OR public.can_modify_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: events rls_events_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_events_insert ON public.events FOR INSERT WITH CHECK ((public.is_global_admin() OR (organization_id IS NULL) OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: events rls_events_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_events_select ON public.events FOR SELECT USING ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: events rls_events_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_events_update ON public.events FOR UPDATE USING ((public.is_global_admin() OR public.can_modify_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: expected_config_changes rls_expected_config_changes_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_expected_config_changes_delete ON public.expected_config_changes FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: expected_config_changes rls_expected_config_changes_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_expected_config_changes_insert ON public.expected_config_changes FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: expected_config_changes rls_expected_config_changes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_expected_config_changes_select ON public.expected_config_changes FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: expected_config_changes rls_expected_config_changes_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_expected_config_changes_update ON public.expected_config_changes FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: generated_reports rls_generated_reports_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_generated_reports_delete ON public.generated_reports FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: generated_reports rls_generated_reports_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_generated_reports_insert ON public.generated_reports FOR INSERT WITH CHECK (true);


--
-- Name: generated_reports rls_generated_reports_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_generated_reports_select ON public.generated_reports FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: generated_reports rls_generated_reports_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_generated_reports_update ON public.generated_reports FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: generic_deep_links rls_generic_deep_links_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_generic_deep_links_delete ON public.generic_deep_links FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: generic_deep_links rls_generic_deep_links_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_generic_deep_links_insert ON public.generic_deep_links FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: generic_deep_links rls_generic_deep_links_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_generic_deep_links_select ON public.generic_deep_links FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: generic_deep_links rls_generic_deep_links_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_generic_deep_links_update ON public.generic_deep_links FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: grafana_dashboards rls_grafana_dashboards_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_grafana_dashboards_delete ON public.grafana_dashboards FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: grafana_dashboards rls_grafana_dashboards_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_grafana_dashboards_insert ON public.grafana_dashboards FOR INSERT WITH CHECK (true);


--
-- Name: grafana_dashboards rls_grafana_dashboards_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_grafana_dashboards_select ON public.grafana_dashboards FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: grafana_dashboards rls_grafana_dashboards_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_grafana_dashboards_update ON public.grafana_dashboards FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: grafana_instances rls_grafana_instances_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_grafana_instances_delete ON public.grafana_instances FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: grafana_instances rls_grafana_instances_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_grafana_instances_insert ON public.grafana_instances FOR INSERT WITH CHECK (true);


--
-- Name: grafana_instances rls_grafana_instances_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_grafana_instances_select ON public.grafana_instances FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: grafana_instances rls_grafana_instances_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_grafana_instances_update ON public.grafana_instances FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: graph_presets rls_graph_presets_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_graph_presets_delete ON public.graph_presets FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: graph_presets rls_graph_presets_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_graph_presets_insert ON public.graph_presets FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: graph_presets rls_graph_presets_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_graph_presets_select ON public.graph_presets FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: graph_presets rls_graph_presets_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_graph_presets_update ON public.graph_presets FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: notification_channels rls_notification_channels_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_notification_channels_delete ON public.notification_channels FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: notification_channels rls_notification_channels_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_notification_channels_insert ON public.notification_channels FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: notification_channels rls_notification_channels_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_notification_channels_select ON public.notification_channels FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: notification_channels rls_notification_channels_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_notification_channels_update ON public.notification_channels FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: profiles rls_profiles_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_profiles_delete ON public.profiles FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: profiles rls_profiles_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_profiles_insert ON public.profiles FOR INSERT WITH CHECK (true);


--
-- Name: profiles rls_profiles_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_profiles_select ON public.profiles FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: profiles rls_profiles_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_profiles_update ON public.profiles FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: pyroscope_instances rls_pyroscope_instances_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_pyroscope_instances_delete ON public.pyroscope_instances FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: pyroscope_instances rls_pyroscope_instances_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_pyroscope_instances_insert ON public.pyroscope_instances FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: pyroscope_instances rls_pyroscope_instances_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_pyroscope_instances_select ON public.pyroscope_instances FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: pyroscope_instances rls_pyroscope_instances_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_pyroscope_instances_update ON public.pyroscope_instances FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: report_templates rls_report_templates_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_report_templates_delete ON public.report_templates FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: report_templates rls_report_templates_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_report_templates_insert ON public.report_templates FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: report_templates rls_report_templates_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_report_templates_select ON public.report_templates FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: report_templates rls_report_templates_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_report_templates_update ON public.report_templates FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: systems_under_test rls_systems_under_test_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_systems_under_test_delete ON public.systems_under_test FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: systems_under_test rls_systems_under_test_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_systems_under_test_insert ON public.systems_under_test FOR INSERT WITH CHECK (true);


--
-- Name: systems_under_test rls_systems_under_test_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_systems_under_test_select ON public.systems_under_test FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: systems_under_test rls_systems_under_test_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_systems_under_test_update ON public.systems_under_test FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: test_runs rls_test_runs_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_test_runs_delete ON public.test_runs FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: test_runs rls_test_runs_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_test_runs_insert ON public.test_runs FOR INSERT WITH CHECK (true);


--
-- Name: test_runs rls_test_runs_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_test_runs_select ON public.test_runs FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: test_runs rls_test_runs_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_test_runs_update ON public.test_runs FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: tracing_instances rls_tracing_instances_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_tracing_instances_delete ON public.tracing_instances FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: tracing_instances rls_tracing_instances_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_tracing_instances_insert ON public.tracing_instances FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: tracing_instances rls_tracing_instances_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_tracing_instances_select ON public.tracing_instances FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: tracing_instances rls_tracing_instances_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_tracing_instances_update ON public.tracing_instances FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: tracing_services rls_tracing_services_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_tracing_services_delete ON public.tracing_services FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: tracing_services rls_tracing_services_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_tracing_services_insert ON public.tracing_services FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: tracing_services rls_tracing_services_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_tracing_services_select ON public.tracing_services FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: tracing_services rls_tracing_services_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_tracing_services_update ON public.tracing_services FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: trends_filter_presets rls_trends_filter_presets_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_trends_filter_presets_delete ON public.trends_filter_presets FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: trends_filter_presets rls_trends_filter_presets_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_trends_filter_presets_insert ON public.trends_filter_presets FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: trends_filter_presets rls_trends_filter_presets_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_trends_filter_presets_select ON public.trends_filter_presets FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: trends_filter_presets rls_trends_filter_presets_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_trends_filter_presets_update ON public.trends_filter_presets FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: url_patterns rls_url_patterns_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_url_patterns_delete ON public.url_patterns FOR DELETE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: url_patterns rls_url_patterns_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_url_patterns_insert ON public.url_patterns FOR INSERT WITH CHECK ((public.is_global_admin() OR public.can_access_resource(organization_id, team_id, (created_by)::text)));


--
-- Name: url_patterns rls_url_patterns_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_url_patterns_select ON public.url_patterns FOR SELECT USING (public.can_access_resource(organization_id, team_id, (created_by)::text));


--
-- Name: url_patterns rls_url_patterns_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rls_url_patterns_update ON public.url_patterns FOR UPDATE USING (public.can_modify_resource(organization_id, team_id, (created_by)::text));


--
-- Name: systems_under_test; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.systems_under_test ENABLE ROW LEVEL SECURITY;

--
-- Name: test_runs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.test_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: tracing_instances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tracing_instances ENABLE ROW LEVEL SECURITY;

--
-- Name: tracing_services; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tracing_services ENABLE ROW LEVEL SECURITY;

--
-- Name: trends_filter_presets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.trends_filter_presets ENABLE ROW LEVEL SECURITY;

--
-- Name: url_patterns; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.url_patterns ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--


