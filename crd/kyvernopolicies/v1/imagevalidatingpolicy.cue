package v1

#ImageValidatingPolicy: {

	// APIVersion defines the versioned schema of this representation of an object.
	// Servers should convert recognized schemas to the latest internal value, and
	// may reject unrecognized values.
	// More info:
	// https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources
	apiVersion?: string

	// Kind is a string value representing the REST resource this object represents.
	// Servers may infer this from the endpoint the client submits requests to.
	// Cannot be updated.
	// In CamelCase.
	// More info:
	// https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
	kind?:     string
	metadata?: {}

	// ImageValidatingPolicySpec is the specification of the desired behavior of the
	// ImageValidatingPolicy.
	spec!: {
		// Attestations provides a list of image metadata to verify
		attestations?: [...{
			// InToto defines the details of attestation attached using intoto format
			intoto?: {
				// Type defines the type of attestation contained within the statement.
				type!: string
			}

			// Name is the name for this attestation. It is used to refer to the attestation in verification
			name!: string

			// Referrer defines the details of attestation attached using OCI 1.1 format
			referrer?: {
				// Type defines the type of attestation attached to the image.
				type!: string
			}
		}]

		// Attestors provides a list of trusted authorities.
		attestors!: [...matchN(1, [{cosign!: _}, {notary!: _}]) & {
			// Cosign defines attestor configuration for Cosign based signatures
			cosign?: {
				// Annotations are used for image verification.
				// Every specified key-value pair must exist and match in the verified payload.
				// The payload may contain other key-value pairs.
				annotations?: [string]: string

				// Certificate defines the configuration for local signature verification
				certificate?: {
					// Certificate is the to the public certificate for local signature verification.
					cert?: matchN(1, [{value!: _}, {expression!: _}]) & {
						// Expression defines the a CEL expression input.
						expression?: string

						// Value defines the raw string input.
						value?: string
					}

					// CertificateChain is the list of CA certificates in PEM format which will be needed
					// when building the certificate chain for the signing certificate. Must start with the
					// parent intermediate CA certificate of the signing certificate and end with the root certificate
					certChain?: matchN(1, [{value!: _}, {expression!: _}]) & {
						// Expression defines the a CEL expression input.
						expression?: string

						// Value defines the raw string input.
						value?: string
					}
				}

				// CTLog sets the configuration to verify the authority against a Rekor instance.
				ctlog?: {
					// CTLogPubKey, if set, is used to validate SCTs against a custom source.
					ctLogPubKey?: string

					// IgnoreSCT defines whether to use the Signed Certificate Timestamp (SCT) log
					// to check for a certificate
					// timestamp. Default is false. Set to true if this was opted out during signing.
					insecureIgnoreSCT?: bool

					// InsecureIgnoreTlog skips transparency log verification.
					insecureIgnoreTlog?: bool

					// RekorPubKey is an optional PEM-encoded public key to use for a custom Rekor.
					// If set, this will be used to validate transparency log signatures from a custom Rekor.
					rekorPubKey?: string

					// TSACertChain, if set, is the PEM-encoded certificate chain file for the
					// RFC3161 timestamp authority. Must
					// contain the root CA certificate. Optionally may contain intermediate CA certificates, and
					// may contain the leaf TSA certificate if not present in the timestamurce.
					tsaCertChain?: string

					// URL sets the url to the rekor instance (by default the public rekor.sigstore.dev)
					url?: string
				}

				// Key defines the type of key to validate the image.
				key?: {
					// Data contains the inline public key
					data?: string

					// Expression is a Expression expression that returns the public key.
					expression?: string

					// HashAlgorithm specifues signature algorithm for public keys. Supported values are
					// sha224, sha256, sha384 and sha512. Defaults to sha256.
					hashAlgorithm?: string

					// KMS contains the KMS url of the public key
					// Supported formats differ based on the KMS system used.
					kms?: string
				}

				// Keyless sets the configuration to verify the authority against a Fulcio instance.
				keyless?: {
					// AdditionalExtensions are certificate-extensions used for keyless signing.
					additionalExtensions?: [string]: string

					// Identities sets a list of identities.
					identities!: [...{
						// Issuer defines the issuer for this identity.
						issuer?: string

						// IssuerRegExp specifies a regular expression to match the issuer for this identity.
						issuerRegExp?: string

						// Subject defines the subject for this identity.
						subject?: string

						// SubjectExpression defines a CEL expression that evaluates to the subject string,
						// matched as a regexp against the certificate SAN URI. Mutually exclusive with SubjectRegExp.
						subjectExpression?: string

						// SubjectRegExp specifies a regular expression to match the subject for this identity.
						subjectRegExp?: string
					}]

					// Roots is an optional set of PEM encoded trusted root certificates.
					// If not provided, the system roots are used.
					roots?: string
				}

				// Sources sets the configuration to specify the sources from where to consume
				// the signature and attestations.
				source?: {
					// SignaturePullSecrets is an optional list of references to secrets in the
					// same namespace as the deploying resource for pulling any of the signatures
					// used by this Source.
					PullSecrets?: [...{
						// Name of the referent.
						// This field is effectively required, but due to backwards compatibility is
						// allowed to be empty. Instances of this type with an empty value here are
						// almost certainly wrong.
						// More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names
						name?: string
					}]

					// Repository defines the location from where to pull the signature / attestations.
					repository?: string

					// TagPrefix is an optional prefix that signature and attestations have.
					// This is the 'tag based discovery' and in the future once references are
					// fully supported that should likely be the preferred way to handle these.
					tagPrefix?: string
				}

				// TrustedRoot is the sigstore-go TrustedRoot JSON
				// (mediaType application/vnd.dev.sigstore.trustedroot+json;version=0.1).
				// When set, Kyverno uses this trust material directly instead of fetching
				// trusted_root.json from the Sigstore TUF repository. Use this field when
				// verifying attestations from providers that do not operate a TUF server,
				// such as GitHub Actions. Takes precedence over the tuf field.
				// Supports an inline JSON value or a CEL expression (e.g. variables.myRoot).
				trustedRoot?: matchN(1, [{value!: _}, {expression!: _}]) & {
					// Expression defines the a CEL expression input.
					expression?: string

					// Value defines the raw string input.
					value?: string
				}

				// TUF defines the configuration to fetch sigstore root
				tuf?: {
					// Mirror is the base URL of Sigstore TUF repository
					mirror?: string

					// Root defines the path or data of the trusted root
					root?: {
						// Data is the base64 encoded TUF root
						data?: string

						// Path is the URL or File location of the TUF root
						path?: string
					}
				}
			}

			// Name is the name for this attestor. It is used to refer to the attestor in verification
			name!: string

			// Notary defines attestor configuration for Notary based signatures
			notary?: {
				// Certs define the cert chain for Notary signature verification
				certs?: matchN(1, [{value!: _}, {expression!: _}]) & {
					// Expression defines the a CEL expression input.
					expression?: string

					// Value defines the raw string input.
					value?: string
				}

				// TSACerts define the cert chain for verifying timestamps of notary signature
				tsaCerts?: matchN(1, [{value!: _}, {expression!: _}]) & {
					// Expression defines the a CEL expression input.
					expression?: string

					// Value defines the raw string input.
					value?: string
				}
			}
		}]

		// auditAnnotations contains CEL expressions which are used to produce audit
		// annotations for the audit event of the API request.
		// validations and auditAnnotations may not both be empty; a least one of
		// validations or auditAnnotations is
		// required.
		auditAnnotations?: [...{
			// key specifies the audit annotation key. The audit annotation keys of
			// a ValidatingAdmissionPolicy must be unique. The key must be a qualified
			// name ([A-Za-z0-9][-A-Za-z0-9_.]*) no more than 63 bytes in length.
			//
			// The key is combined with the resource name of the
			// ValidatingAdmissionPolicy to construct an audit annotation key:
			// "{ValidatingAdmissionPolicy name}/{key}".
			//
			// If an admission webhook uses the same resource name as this ValidatingAdmissionPolicy
			// and the same audit annotation key, the annotation key will be identical.
			// In this case, the first annotation written with the key will be included
			// in the audit event and all subsequent annotations with the same key
			// will be discarded.
			//
			// Required.
			key!: string

			// valueExpression represents the expression which is evaluated by CEL to
			// produce an audit annotation value. The expression must evaluate to either
			// a string or null value. If the expression evaluates to a string, the
			// audit annotation is included with the string value. If the expression
			// evaluates to null or empty string the audit annotation will be omitted.
			// The valueExpression may be no longer than 5kb in length.
			// If the result of the valueExpression is more than 10kb in length, it
			// will be truncated to 10kb.
			//
			// If multiple ValidatingAdmissionPolicyBinding resources match an
			// API request, then the valueExpression will be evaluated for
			// each binding. All unique values produced by the valueExpressions
			// will be joined together in a comma-separated list.
			//
			// Required.
			valueExpression!: string
		}]

		// AutogenConfiguration defines the configuration for the generation controller.
		autogen?: {
			// PodControllers specifies whether to generate a pod controllers rules.
			podControllers?: controllers?: [...string]
		}

		// Credentials provides credentials that will be used for authentication with registry.
		credentials?: {
			// AllowInsecureRegistry allows insecure access to a registry.
			allowInsecureRegistry?: bool

			// Providers specifies a list of OCI Registry names, whose authentication providers are provided.
			// It can be of one of these values: default,google,azure,amazon,github.
			providers?: [..."default" | "amazon" | "azure" | "google" | "github"]

			// Secrets specifies a list of secrets that are provided for credentials.
			// Secrets must live in the Kyverno namespace.
			secrets?: [...string]
		}

		// EvaluationConfiguration defines the configuration for the policy evaluation.
		evaluation?: {
			// Admission controls policy evaluation during admission.
			admission?: {
				// Enabled controls if rules are applied during admission.
				// Optional. Default value is "true".
				enabled?: bool
			}

			// Background controls policy evaluation during background scan.
			background?: {
				// Enabled controls if rules are applied to existing resources during a background scan.
				// Optional. Default value is "true". The value must be set to "false" if the policy rule
				// uses variables that are only available in the admission review request (e.g. user name).
				enabled?: bool
			}

			// Mode is the mode of policy evaluation.
			// Allowed values are "Kubernetes", "HTTP" or "Envoy".
			// Optional. Default value is "Kubernetes".
			mode?: string
		}

		// FailurePolicy defines how to handle failures for the admission policy. Failures can
		// occur from CEL expression parse errors, type check errors, runtime errors and invalid
		// or mis-configured policy definitions or bindings.
		failurePolicy?: "Ignore" | "Fail"

		// ImageExtractors is a list of CEL expression to extract images from the resource
		images?: [...{
			// Expression defines CEL expression to extract images from the resource.
			expression!: string

			// Name is the name for this imageList. It is used to refer to the images in
			// verification block as images.<name>
			name!: string
		}]

		// MatchConditions is a list of conditions that must be met for a request to be validated.
		// Match conditions filter requests that have already been matched by the rules,
		// namespaceSelector, and objectSelector. An empty list of matchConditions matches all requests.
		// There are a maximum of 64 match conditions allowed.
		matchConditions?: [...{
			// Expression represents the expression which will be evaluated by CEL. Must evaluate to bool.
			// CEL expressions have access to the contents of the AdmissionRequest and
			// Authorizer, organized into CEL variables:
			//
			// 'object' - The object from the incoming request. The value is null for DELETE requests.
			// 'oldObject' - The existing object. The value is null for CREATE requests.
			// 'request' - Attributes of the admission request(/pkg/apis/admission/types.go#AdmissionRequest).
			// 'authorizer' - A CEL Authorizer. May be used to perform authorization checks
			// for the principal (user or service account) of the request.
			// See https://pkg.go.dev/k8s.io/apiserver/pkg/cel/library#Authz
			// 'authorizer.requestResource' - A CEL ResourceCheck constructed from the
			// 'authorizer' and configured with the
			// request resource.
			// Documentation on CEL: https://kubernetes.io/docs/reference/using-api/cel/
			//
			// Required.
			expression!: string

			// Name is an identifier for this match condition, used for strategic merging of MatchConditions,
			// as well as providing an identifier for logging purposes. A good name should be descriptive of
			// the associated expression.
			// Name must be a qualified name consisting of alphanumeric characters, '-', '_' or '.', and
			// must start and end with an alphanumeric character (e.g. 'MyName', or 'my.name', or
			// '123-abc', regex used for validation is '([A-Za-z0-9][-A-Za-z0-9_.]*)?[A-Za-z0-9]') with an
			// optional DNS subdomain prefix and '/' (e.g. 'example.com/MyName')
			//
			// Required.
			name!: string
		}]

		// MatchConstraints specifies what resources this policy is designed to validate.
		matchConstraints?: {
			// ExcludeResourceRules describes what operations on what resources/subresources
			// the ValidatingAdmissionPolicy should not care about.
			// The exclude rules take precedence over include rules (if a resource matches both, it is excluded)
			excludeResourceRules?: [...{
				// APIGroups is the API groups the resources belong to. '*' is all groups.
				// If '*' is present, the length of the slice must be one.
				// Required.
				apiGroups?: [...string]

				// APIVersions is the API versions the resources belong to. '*' is all versions.
				// If '*' is present, the length of the slice must be one.
				// Required.
				apiVersions?: [...string]

				// Operations is the operations the admission hook cares about - CREATE, UPDATE,
				// DELETE, CONNECT or *
				// for all of those operations and any future admission operations that are added.
				// If '*' is present, the length of the slice must be one.
				// Required.
				operations?: [...string]

				// ResourceNames is an optional white list of names that the rule applies to. An
				// empty set means that everything is allowed.
				resourceNames?: [...string]

				// Resources is a list of resources this rule applies to.
				//
				// For example:
				// 'pods' means pods.
				// 'pods/log' means the log subresource of pods.
				// '*' means all resources, but not subresources.
				// 'pods/*' means all subresources of pods.
				// '*/scale' means all scale subresources.
				// '*/*' means all resources and their subresources.
				//
				// If wildcard is present, the validation rule will ensure resources do not
				// overlap with each other.
				//
				// Depending on the enclosing object, subresources might not be allowed.
				// Required.
				resources?: [...string]

				// scope specifies the scope of this rule.
				// Valid values are "Cluster", "Namespaced", and "*"
				// "Cluster" means that only cluster-scoped resources will match this rule.
				// Namespace API objects are cluster-scoped.
				// "Namespaced" means that only namespaced resources will match this rule.
				// "*" means that there are no scope restrictions.
				// Subresources match the scope of their parent resource.
				// Default is "*".
				scope?: string
			}]

			// matchPolicy defines how the "MatchResources" list is used to match incoming requests.
			// Allowed values are "Exact" or "Equivalent".
			//
			// - Exact: match a request only if it exactly matches a specified rule.
			// For example, if deployments can be modified via apps/v1, apps/v1beta1, and extensions/v1beta1,
			// but "rules" only included `apiGroups:["apps"], apiVersions:["v1"], resources: ["deployments"]`,
			// a request to apps/v1beta1 or extensions/v1beta1 would not be sent to the
			// ValidatingAdmissionPolicy.
			//
			// - Equivalent: match a request if modifies a resource listed in rules, even
			// via another API group or version.
			// For example, if deployments can be modified via apps/v1, apps/v1beta1, and extensions/v1beta1,
			// and "rules" only included `apiGroups:["apps"], apiVersions:["v1"], resources: ["deployments"]`,
			// a request to apps/v1beta1 or extensions/v1beta1 would be converted to apps/v1
			// and sent to the ValidatingAdmissionPolicy.
			//
			// Defaults to "Equivalent"
			matchPolicy?: string

			// NamespaceSelector decides whether to run the admission control policy on an object based
			// on whether the namespace for that object matches the selector. If the
			// object itself is a namespace, the matching is performed on
			// object.metadata.labels. If the object is another cluster scoped resource,
			// it never skips the policy.
			//
			// For example, to run the webhook on any objects whose namespace is not
			// associated with "runlevel" of "0" or "1"; you will set the selector as
			// follows:
			// "namespaceSelector": {
			// "matchExpressions": [
			// {
			// "key": "runlevel",
			// "operator": "NotIn",
			// "values": [
			// "0",
			// "1"
			// ]
			// }
			// ]
			// }
			//
			// If instead you want to only run the policy on any objects whose
			// namespace is associated with the "environment" of "prod" or "staging";
			// you will set the selector as follows:
			// "namespaceSelector": {
			// "matchExpressions": [
			// {
			// "key": "environment",
			// "operator": "In",
			// "values": [
			// "prod",
			// "staging"
			// ]
			// }
			// ]
			// }
			//
			// See
			// https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/
			// for more examples of label selectors.
			//
			// Default to the empty LabelSelector, which matches everything.
			namespaceSelector?: {
				// matchExpressions is a list of label selector requirements. The requirements are ANDed.
				matchExpressions?: [...{
					// key is the label key that the selector applies to.
					key!: string

					// operator represents a key's relationship to a set of values.
					// Valid operators are In, NotIn, Exists and DoesNotExist.
					operator!: string

					// values is an array of string values. If the operator is In or NotIn,
					// the values array must be non-empty. If the operator is Exists or DoesNotExist,
					// the values array must be empty. This array is replaced during a strategic
					// merge patch.
					values?: [...string]
				}]

				// matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels
				// map is equivalent to an element of matchExpressions, whose key field is "key", the
				// operator is "In", and the values array contains only "value". The requirements are ANDed.
				matchLabels?: [string]: string
			}

			// ObjectSelector decides whether to run the validation based on if the
			// object has matching labels. objectSelector is evaluated against both
			// the oldObject and newObject that would be sent to the cel validation, and
			// is considered to match if either object matches the selector. A null
			// object (oldObject in the case of create, or newObject in the case of
			// delete) or an object that cannot have labels (like a
			// DeploymentRollback or a PodProxyOptions object) is not considered to
			// match.
			// Use the object selector only if the webhook is opt-in, because end
			// users may skip the admission webhook by setting the labels.
			// Default to the empty LabelSelector, which matches everything.
			objectSelector?: {
				// matchExpressions is a list of label selector requirements. The requirements are ANDed.
				matchExpressions?: [...{
					// key is the label key that the selector applies to.
					key!: string

					// operator represents a key's relationship to a set of values.
					// Valid operators are In, NotIn, Exists and DoesNotExist.
					operator!: string

					// values is an array of string values. If the operator is In or NotIn,
					// the values array must be non-empty. If the operator is Exists or DoesNotExist,
					// the values array must be empty. This array is replaced during a strategic
					// merge patch.
					values?: [...string]
				}]

				// matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels
				// map is equivalent to an element of matchExpressions, whose key field is "key", the
				// operator is "In", and the values array contains only "value". The requirements are ANDed.
				matchLabels?: [string]: string
			}

			// ResourceRules describes what operations on what resources/subresources the
			// ValidatingAdmissionPolicy matches.
			// The policy cares about an operation if it matches _any_ Rule.
			resourceRules?: [...{
				// APIGroups is the API groups the resources belong to. '*' is all groups.
				// If '*' is present, the length of the slice must be one.
				// Required.
				apiGroups?: [...string]

				// APIVersions is the API versions the resources belong to. '*' is all versions.
				// If '*' is present, the length of the slice must be one.
				// Required.
				apiVersions?: [...string]

				// Operations is the operations the admission hook cares about - CREATE, UPDATE,
				// DELETE, CONNECT or *
				// for all of those operations and any future admission operations that are added.
				// If '*' is present, the length of the slice must be one.
				// Required.
				operations?: [...string]

				// ResourceNames is an optional white list of names that the rule applies to. An
				// empty set means that everything is allowed.
				resourceNames?: [...string]

				// Resources is a list of resources this rule applies to.
				//
				// For example:
				// 'pods' means pods.
				// 'pods/log' means the log subresource of pods.
				// '*' means all resources, but not subresources.
				// 'pods/*' means all subresources of pods.
				// '*/scale' means all scale subresources.
				// '*/*' means all resources and their subresources.
				//
				// If wildcard is present, the validation rule will ensure resources do not
				// overlap with each other.
				//
				// Depending on the enclosing object, subresources might not be allowed.
				// Required.
				resources?: [...string]

				// scope specifies the scope of this rule.
				// Valid values are "Cluster", "Namespaced", and "*"
				// "Cluster" means that only cluster-scoped resources will match this rule.
				// Namespace API objects are cluster-scoped.
				// "Namespaced" means that only namespaced resources will match this rule.
				// "*" means that there are no scope restrictions.
				// Subresources match the scope of their parent resource.
				// Default is "*".
				scope?: string
			}]
		}

		// MatchImageReferences is a list of Glob and CELExpressions to match images.
		// Any image that matches one of the rules is considered for validation
		// Any image that does not match a rule is skipped, even when they are passed as arguments to
		// image verification functions
		matchImageReferences?: [...matchN(1, [{glob!: _}, {expression!: _}]) & {
			// Expression defines CEL Expressions for matching images
			expression?: string

			// Glob defines a globbing pattern for matching images
			glob?: string
		}]

		// ValidationAction specifies the action to be taken when the matched resource violates the policy.
		// If a validation evaluates to false it is always enforced according to these actions.
		//
		// Failures defined by the ValidatingAdmissionPolicy's FailurePolicy are enforced according
		// to these actions only if the FailurePolicy is set to Fail, otherwise the failures are
		// ignored. This includes compilation errors, runtime errors and misconfigurations of the policy.
		//
		// validationActions is declared as a set of action values. Order does
		// not matter. validationActions may not contain duplicates of the same action.
		//
		// The supported actions values are:
		//
		// "Deny" specifies that a validation failure results in a denied request.
		//
		// "Warn" specifies that a validation failure is reported to the request client
		// in HTTP Warning headers, with a warning code of 299. Warnings can be sent
		// both for allowed or denied admission responses.
		//
		// "Audit" specifies that a validation failure is recorded in the created reports.
		//
		// Clients should expect to handle additional values by ignoring
		// any values not recognized.
		//
		// "Deny" and "Warn" may not be used together since this combination
		// needlessly duplicates the validation failure both in the
		// API response body and the HTTP warning headers.
		//
		// Required.
		validationActions?: [..."Deny" | "Audit" | "Warn"]

		// ValidationConfigurations defines settings for mutating and verifying image
		// digests, and enforcing image verification through signatures.
		validationConfigurations?: {
			// MutateDigest enables replacement of image tags with digests.
			// Defaults to true.
			mutateDigest?: bool

			// Required validates that images are verified, i.e., have passed a signature or attestation check.
			required?: bool

			// VerifyDigest validates that images have a digest.
			verifyDigest?: bool
		}

		// Validations contain CEL expressions which is used to apply the image validation checks.
		validations!: [...{
			// Expression represents the expression which will be evaluated by CEL.
			// ref: https://github.com/google/cel-spec
			// CEL expressions have access to the contents of the API request/response,
			// organized into CEL variables as well as some other useful variables:
			//
			// - 'object' - The object from the incoming request. The value is null for DELETE requests.
			// - 'oldObject' - The existing object. The value is null for CREATE requests.
			// - 'request' - Attributes of the API
			// request([ref](/pkg/apis/admission/types.go#AdmissionRequest)).
			// - 'params' - Parameter resource referred to by the policy binding being
			// evaluated. Only populated if the policy has a ParamKind.
			// - 'namespaceObject' - The namespace object that the incoming object belongs
			// to. The value is null for cluster-scoped resources.
			// - 'variables' - Map of composited variables, from its name to its lazily evaluated value.
			// For example, a variable named 'foo' can be accessed as 'variables.foo'.
			// - 'authorizer' - A CEL Authorizer. May be used to perform authorization
			// checks for the principal (user or service account) of the request.
			// See https://pkg.go.dev/k8s.io/apiserver/pkg/cel/library#Authz
			// - 'authorizer.requestResource' - A CEL ResourceCheck constructed from the
			// 'authorizer' and configured with the
			// request resource.
			//
			// The `apiVersion`, `kind`, `metadata.name` and `metadata.generateName` are
			// always accessible from the root of the
			// object. No other metadata properties are accessible.
			//
			// Only property names of the form `[a-zA-Z_.-/][a-zA-Z0-9_.-/]*` are accessible.
			// Accessible property names are escaped according to the following rules when
			// accessed in the expression:
			// - '__' escapes to '__underscores__'
			// - '.' escapes to '__dot__'
			// - '-' escapes to '__dash__'
			// - '/' escapes to '__slash__'
			// - Property names that exactly match a CEL RESERVED keyword escape to
			// '__{keyword}__'. The keywords are:
			// "true", "false", "null", "in", "as", "break", "const", "continue", "else",
			// "for", "function", "if",
			// "import", "let", "loop", "package", "namespace", "return".
			// Examples:
			// - Expression accessing a property named "namespace": {"Expression": "object.__namespace__ > 0"}
			// - Expression accessing a property named "x-prop": {"Expression": "object.x__dash__prop > 0"}
			// - Expression accessing a property named "redact__d": {"Expression":
			// "object.redact__underscores__d > 0"}
			//
			// Equality on arrays with list type of 'set' or 'map' ignores element order, i.e. [1, 2] == [2, 1].
			// Concatenation on arrays with x-kubernetes-list-type use the semantics of the list type:
			// - 'set': `X + Y` performs a union where the array positions of all elements
			// in `X` are preserved and
			// non-intersecting elements in `Y` are appended, retaining their partial order.
			// - 'map': `X + Y` performs a merge where the array positions of all keys in
			// `X` are preserved but the values
			// are overwritten by values in `Y` when the key sets of `X` and `Y` intersect. Elements in `Y` with
			// non-intersecting keys are appended, retaining their partial order.
			// Required.
			expression!: string

			// Message represents the message displayed when validation fails. The message
			// is required if the Expression contains
			// line breaks. The message must not contain line breaks.
			// If unset, the message is "failed rule: {Rule}".
			// e.g. "must be a URL with the host matching spec.host"
			// If the Expression contains line breaks. Message is required.
			// The message must not contain line breaks.
			// If unset, the message is "failed Expression: {Expression}".
			message?: string

			// messageExpression declares a CEL expression that evaluates to the validation
			// failure message that is returned when this rule fails.
			// Since messageExpression is used as a failure message, it must evaluate to a string.
			// If both message and messageExpression are present on a validation, then
			// messageExpression will be used if validation fails.
			// If messageExpression results in a runtime error, the runtime error is logged,
			// and the validation failure message is produced
			// as if the messageExpression field were unset. If messageExpression evaluates
			// to an empty string, a string with only spaces, or a string
			// that contains line breaks, then the validation failure message will also be
			// produced as if the messageExpression field were unset, and
			// the fact that messageExpression produced an empty string/string with only
			// spaces/string with line breaks will be logged.
			// messageExpression has access to all the same variables as the `expression`
			// except for 'authorizer' and 'authorizer.requestResource'.
			// Example:
			// "object.x must be less than max ("+string(params.max)+")"
			messageExpression?: string

			// Reason represents a machine-readable description of why this validation failed.
			// If this is the first validation in the list to fail, this reason, as well as the
			// corresponding HTTP response code, are used in the
			// HTTP response to the client.
			// The currently supported reasons are: "Unauthorized", "Forbidden", "Invalid",
			// "RequestEntityTooLarge".
			// If not set, StatusReasonInvalid is used in the response to the client.
			reason?: string
		}]

		// Variables contain definitions of variables that can be used in composition of other expressions.
		// Each variable is defined as a named CEL expression.
		variables?: [...{
			// Expression is the expression that will be evaluated as the value of the variable.
			// The CEL expression has access to the same identifiers as the CEL expressions in Validation.
			expression!: string

			// Name is the name of the variable. The name must be a valid CEL identifier and
			// unique among all variables.
			// The variable can be accessed in other expressions through `variables`
			// For example, if name is "foo", the variable will be available as `variables.foo`
			name!: string
		}]

		// WebhookConfiguration defines the configuration for the webhook.
		webhookConfiguration?: {
			// TimeoutSeconds specifies the maximum time in seconds allowed to apply this policy.
			// After the configured time expires, the admission request may fail, or may
			// simply ignore the policy results,
			// based on the failure policy. The default timeout is 10s, the value must be
			// between 1 and 30 seconds.
			timeoutSeconds?: int32 & int
		}
	}
	apiVersion: "policies.kyverno.io/v1"
	kind:       "ImageValidatingPolicy"
	metadata!: {
		name!:      string
		namespace?: string
		labels?: [string]:      string
		annotations?: [string]: string
	}
}
