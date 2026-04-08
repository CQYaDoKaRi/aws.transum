#nullable enable
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Amazon;
using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;

namespace AudioTranscriptionSummary.Services;

public class S3Service
{
    private readonly AmazonS3Client _client;

    /// <summary>
    /// AWSCredentials と RegionEndpoint を受け取るコンストラクタ（AWSClientFactory 経由用）
    /// </summary>
    public S3Service(AWSCredentials credentials, RegionEndpoint region)
    {
        _client = new AmazonS3Client(credentials, region);
    }

    /// <summary>
    /// Access Key / Secret Key / Region 文字列を受け取るコンストラクタ（後方互換性用）
    /// </summary>
    public S3Service(string accessKeyId, string secretAccessKey, string region)
    {
        var credentials = new BasicAWSCredentials(accessKeyId, secretAccessKey);
        _client = new AmazonS3Client(credentials, RegionEndpoint.GetBySystemName(region));
    }

    public static string GenerateKey(string extension)
    {
        var ext = extension.TrimStart('.');
        return $"{Guid.NewGuid()}.{ext}";
    }

    public async Task UploadAsync(string bucket, string key, string filePath, CancellationToken ct = default)
    {
        var request = new PutObjectRequest
        {
            BucketName = bucket,
            Key = key,
            FilePath = filePath
        };
        await _client.PutObjectAsync(request, ct);
    }

    public async Task DeleteAsync(string bucket, string key, CancellationToken ct = default)
    {
        var request = new DeleteObjectRequest
        {
            BucketName = bucket,
            Key = key
        };
        await _client.DeleteObjectAsync(request, ct);
    }
}
